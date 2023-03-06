# "AWS Cloud Technical Essentials" exercises done in Terraform

This Terraform configuration builds the setup of exercises 2-7 of AWS' "Cloud
Technical Essentials" course, with a few differences:

* The EC2 instances hosting the Employee Directory app have been moved
  to private subnets. This avoids them getting a public IP of their
  own, which they don't need because they're behind a load balancer.
* A NAT gateway is added so the EC2 instances can still make outbound
  connections, despite being in a private subnet. For example to download the
  Employee Directory application and software updates.
* IAM roles have been limited slightly in their scope by applying a
  resource filter.
* An optional "Bastion" instance can be deployed to serve as a SSH jump
  host, in case you do want to SSH to the application instances (use with
  `ssh -J ec2-user@public-ip-of-bastion ec2-user@private-ip-of-app-ec2-instance`)

## What's deployed?

* A VPC
* Four subnets in two Availability Zones
* An Internet Gateway and a NAT Gateway
* At least two EC2 instances running the Employee Directory application
* An Auto Scaling Group for these EC2 instances
* An Application Load Balancer
* A S3 bucket for the employee photos
* A DynmoDB table for the employee details
* The necessary IAM roles and Security Groups
* A (SSH) key pair
* (Optionally) An EC2 instance serving as a SSH jump host
