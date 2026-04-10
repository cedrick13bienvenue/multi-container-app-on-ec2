output "security_group_id" {
  description = "ID of the security group — passed to ec2 module"
  value       = aws_security_group.app_sg.id
}
