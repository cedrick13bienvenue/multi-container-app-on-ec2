variable "aws_region" {
  description = "AWS region where all resources will be deployed"
  type        = string
  default     = "eu-west-1"
}

variable "my_ip" {
  description = "Your public IP in CIDR notation (e.g. x.x.x.x/32) — restricts SSH to your machine only"
  type        = string
}

variable "ami_id" {
  description = "Amazon Linux 2 AMI ID for eu-west-1"
  type        = string
  default     = "ami-03fc391f1833b0d72"
}

variable "instance_type" {
  description = "EC2 instance type — t3.micro is Free Tier eligible in eu-west-1"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Tag prefix applied to all resources for easy identification"
  type        = string
  default     = "multi-container-app"
}
