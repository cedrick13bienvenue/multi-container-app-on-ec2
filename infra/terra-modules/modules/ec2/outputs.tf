output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS hostname of the EC2 instance"
  value       = aws_instance.app.public_dns
}
