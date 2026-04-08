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
    region         = "eu-north-1"
    dynamodb_table = "multi-container-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Networking ────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "igw" {
  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

resource "aws_internet_gateway_attachment" "igw" {
  internet_gateway_id = aws_internet_gateway.igw.id
  vpc_id              = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "SSH from my IP only; Flask (5000) from anywhere"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.app_sg.id
  description       = "SSH from my IP only - restricted"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.my_ip
}

resource "aws_vpc_security_group_ingress_rule" "flask" {
  security_group_id = aws_security_group.app_sg.id
  description       = "Flask app - port 5000"
  from_port         = 5000
  to_port           = 5000
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.app_sg.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── SSH Key Pair ──────────────────────────────────────────────────────────────

resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-key"
  public_key = file("${path.module}/../keys/app.pub")
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.app.key_name

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }
}

# Auto-generate inventory.ini after apply — no manual IP hardcoding.
# Ansible reads this file to know which host to connect to.
resource "local_file" "inventory" {
  filename = "${path.module}/inventory.ini"
  content  = <<-EOT
    [app]
    ${aws_instance.app.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=../keys/app ansible_ssh_common_args='-o StrictHostKeyChecking=no' ansible_python_interpreter=/usr/bin/python3
  EOT
}
