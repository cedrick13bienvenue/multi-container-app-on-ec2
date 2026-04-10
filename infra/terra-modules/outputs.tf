output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.subnet_id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = module.ec2.ec2_public_ip
}

output "ec2_public_dns" {
  description = "Public DNS hostname of the EC2 instance"
  value       = module.ec2.ec2_public_dns
}

output "ssh_command" {
  description = "Ready-to-run SSH command"
  value       = "ssh -i ../../keys/app ec2-user@${module.ec2.ec2_public_ip}"
}

output "ansible_command" {
  description = "Run this from infra/ansible/ after apply to configure the instance"
  value       = "cd ../ansible && ansible-playbook -i inventory.ini site.yml"
}

output "app_url" {
  description = "URL to reach the Flask app after docker compose up"
  value       = "http://${module.ec2.ec2_public_ip}:5000"
}
