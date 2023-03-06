provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "AWSCloudTechnicalEssentials"
      Terraform = "true"
    }
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "app-vpc"
  cidr = "10.1.0.0/16"

  azs                  = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets       = ["10.1.1.0/24", "10.1.2.0/24"]
  public_subnet_names  = ["Public Subnet 1", "Public Subnet 2"]
  private_subnets      = ["10.1.3.0/24", "10.1.4.0/24"]
  private_subnet_names = ["Private Subnet 1", "Private Subnet 2"]

  create_igw         = true
  enable_nat_gateway = true
  single_nat_gateway = true
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ssh_key" {
  public_key = file(var.ssh_key_pair)
}

resource "aws_iam_role" "S3DynamoDBFullAccessRole" {
  name = "S3DynamoDBFullAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement : [
      {
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Principal = {
          Service : ["ec2.amazonaws.com"]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "S3FullAccessPolicy" {
  name = "S3FullAccessPolicy_${var.employee_photo_s3_bucket_name}"
  role = aws_iam_role.S3DynamoDBFullAccessRole.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${var.employee_photo_s3_bucket_name}/*"
        Action = [
          "s3:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "DynamoDBFullAccessPolicy" {
  name = "DynamoFullAccessPolicy_Employees"
  role = aws_iam_role.S3DynamoDBFullAccessRole.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Resource = "arn:aws:dynamodb:*:*:table/Employees"
        Action = [
          "dynamodb:*"
        ]
      }
    ]
  })
}

resource "aws_security_group" "load_balancer_sg" {
  name   = "load-balancer-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    # Publically accessible
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_app_sg" {
  name   = "app-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    # Allow only traffic from this security group 
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app_alb" {
  load_balancer_type = "application"
  internal           = false
  subnets            = module.vpc.public_subnets

  security_groups = [aws_security_group.load_balancer_sg.id]
}

resource "aws_lb_listener" "app_alb" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_alb.arn
  }
}

resource "aws_lb_target_group" "app_alb" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 40
    timeout             = 30
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

# Alternative to using `target_group_arns` at the `aws_autoscaling_group`
# resource "aws_autoscaling_attachment" "employee-directory-alb" {
#   lb_target_group_arn    = aws_lb_target_group.app-alb-tg.arn
#   autoscaling_group_name = aws_autoscaling_group.employee-directory-asg.id
# }

resource "aws_iam_instance_profile" "employee_directory_web_server" {
  name = "employee-directory-web-server-profile"
  role = aws_iam_role.S3DynamoDBFullAccessRole.name
}

resource "aws_launch_template" "employee_directory_web_server" {
  name_prefix   = "employee-directory-web-server-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  user_data = base64encode(
    templatefile("templates/user_data.sh.tftpl", {
      bucket_name = var.employee_photo_s3_bucket_name,
      aws_region  = var.aws_region
  }))
  key_name = aws_key_pair.ssh_key.key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.employee_directory_web_server.arn
  }

  vpc_security_group_ids = [
    aws_security_group.web_app_sg.id,
    aws_security_group.bastion_sg.id
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "employee_directory_asg" {
  name             = "app-asg"
  min_size         = var.employee_directory_min_instances
  max_size         = var.employee_directory_max_instances
  desired_capacity = var.employee_directory_min_instances

  health_check_grace_period = 300
  health_check_type         = "ELB"

  target_group_arns   = [aws_lb_target_group.app_alb.arn]
  vpc_zone_identifier = module.vpc.private_subnets

  launch_template {
    id      = aws_launch_template.employee_directory_web_server.id
    version = "$Latest"
  }

  # Ignore changes the the capacity and (the load balancer's) target group the
  # can be made by AWS when the number of instances are scaled
  lifecycle {
    ignore_changes = [desired_capacity, target_group_arns]
  }
}

resource "aws_autoscaling_policy" "employee_directory_asp" {
  name                   = "employee-directory-asp"
  autoscaling_group_name = aws_autoscaling_group.employee_directory_asg.name

  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.employee_directory_avg_cpu_usage
  }
}

resource "aws_s3_bucket" "employee_photos" {
  bucket = var.employee_photo_s3_bucket_name
}

resource "aws_s3_bucket_acl" "employee_photos_acl" {
  bucket = aws_s3_bucket.employee_photos.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "employee_photos_bucket_policy" {
  bucket = aws_s3_bucket.employee_photos.id
  policy = templatefile("templates/s3_bucket_policy.json.tftpl", {
    aws_account_number = var.aws_account_number
    bucket_name        = var.employee_photo_s3_bucket_name
  })
}

resource "aws_dynamodb_table" "employees_table" {
  name     = "Employees"
  hash_key = "id"

  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "id"
    type = "S" # Number
  }
}

resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  count         = var.deploy_bastion ? 1 : 0
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.nano"
  subnet_id     = module.vpc.public_subnets[0]

  key_name               = aws_key_pair.ssh_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name        = var.bastion_instance_name
    Description = "SSH jump host"
  }
}
