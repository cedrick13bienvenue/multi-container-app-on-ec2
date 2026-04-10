resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.app.key_name

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }
}
