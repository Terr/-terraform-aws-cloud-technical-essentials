variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_number" {
  description = "AWS account number, used for role ARNs"
  type        = number
}

variable "ssh_key_pair" {
  description = "Public key to be add to the EC2 instances' allow list"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "employee_photo_s3_bucket_name" {
  description = "S3 bucket to store employee photos in"
  type        = string
  default     = "employee-photo-bucket-terr-09032023"
}

variable "employee_directory_min_instances" {
  description = "Minimum number of EC2 instances running the Employee Directory application"
  type        = number
  default     = 2
}

variable "employee_directory_max_instances" {
  description = "Scale up to this maximum of EC2 instances running the Employee Directory application"
  type        = number
  default     = 4
}

variable "employee_directory_avg_cpu_usage" {
  description = "Balance the number of Employee Directory instances to keep the average CPU usage at this number"
  type        = number
  default     = 60.0
}

variable "deploy_bastion" {
  description = "Whether to deploy the Bastion (SSH jump host) EC2 instance"
  type        = bool
  default     = false
}

variable "bastion_instance_name" {
  description = "Value of the Name tag for the Bastion EC2 instance"
  type        = string
  default     = "Bastion"
}
