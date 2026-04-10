# Remote backend: state stored in S3, locked via DynamoDB.
# Run infra/backend first to create these resources.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "cedrick-multi-container-state-2026"
    key            = "multi-container-app/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "multi-container-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Modules ───────────────────────────────────────────────────────────────────

module "vpc" {
  source       = "./modules/vpc"
  aws_region   = var.aws_region
  project_name = var.project_name
}

module "security_group" {
  source       = "./modules/security-group"
  vpc_id       = module.vpc.vpc_id
  my_ip        = var.my_ip
  project_name = var.project_name
}

module "ec2" {
  source            = "./modules/ec2"
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  subnet_id         = module.vpc.subnet_id
  security_group_id = module.security_group.security_group_id
  project_name      = var.project_name
  # Read the public key here in the root module — avoids file() path issues inside child modules
  public_key        = file("../../keys/app.pub")
}

# Auto-generate inventory.ini in the ansible folder after apply.
# Ansible reads this file to know which host to connect to.
resource "local_file" "inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
    [app]
    ${module.ec2.ec2_public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=../../keys/app ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3
  EOT
}
