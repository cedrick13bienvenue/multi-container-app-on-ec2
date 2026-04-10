output "vpc_id" {
  description = "ID of the VPC — passed to security-group and ec2 modules"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet — passed to ec2 module"
  value       = aws_subnet.public.id
}
