output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS hostname of the EC2 instance"
  value       = aws_instance.app.public_dns
}

output "ssh_command" {
  description = "Ready-to-run SSH command"
  value       = "ssh -i ../keys/app ec2-user@${aws_instance.app.public_ip}"
}

output "ansible_command" {
  description = "Run this after apply to configure Docker on the instance"
  value       = "ansible-playbook -i inventory.ini site.yml"
}

output "app_url" {
  description = "URL to reach the Flask app after docker compose up"
  value       = "http://${aws_instance.app.public_ip}:5000"
}
