variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID to attach to the instance"
  type        = string
}

variable "project_name" {
  description = "Tag prefix applied to all EC2 resources"
  type        = string
}

variable "public_key" {
  description = "SSH public key content — read by the root module and passed in as a string"
  type        = string
}
