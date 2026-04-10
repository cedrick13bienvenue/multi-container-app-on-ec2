variable "aws_region" {
  description = "AWS region — used for availability zone selection"
  type        = string
}

variable "project_name" {
  description = "Tag prefix applied to all VPC resources"
  type        = string
}
