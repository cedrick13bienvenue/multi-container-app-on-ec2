variable "vpc_id" {
  description = "VPC ID to attach the security group to"
  type        = string
}

variable "my_ip" {
  description = "Your public IP in CIDR notation — restricts SSH to your machine only"
  type        = string
}

variable "project_name" {
  description = "Tag prefix applied to all security group resources"
  type        = string
}
