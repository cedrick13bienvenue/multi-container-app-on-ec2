# Bootstraps the remote backend — uses local state intentionally.
# Run this first, before the main infra config.
#
# Workflow:
#   1. cd infra/backend && terraform init && terraform apply
#   2. cd ..            && terraform init && terraform apply
#
# Teardown (reverse order):
#   1. cd ..            && terraform destroy -var="my_ip=YOUR.IP/32"
#   2. cd infra/backend && terraform destroy

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 bucket — stores the Terraform state file remotely
resource "aws_s3_bucket" "state" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name    = var.bucket_name
    Purpose = "Terraform remote state"
  }
}

# Versioning — keeps a history of every state file for recovery
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access — state files can contain sensitive data
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# DynamoDB table — prevents concurrent applies from corrupting state
resource "aws_dynamodb_table" "lock" {
  name         = var.dynamodb_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = var.dynamodb_table
    Purpose = "Terraform state locking"
  }
}
