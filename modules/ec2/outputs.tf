output "instance_id" {
  description = "ID of the EC2 instance."
  value       = module.ec2_instance.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance."
  value       = module.ec2_instance.arn
}

output "private_ip" {
  description = "Private IPv4 address of the EC2 instance."
  value       = module.ec2_instance.private_ip
}

output "public_ip" {
  description = "Public IPv4 address of the EC2 instance, when assigned."
  value       = module.ec2_instance.public_ip
}

output "security_group_id" {
  description = "ID of the managed security group; null when creation is disabled."
  value       = module.ec2_instance.security_group_id
}

output "security_group_ids" {
  description = "Managed and existing security group IDs attached to the instance."
  value       = distinct(concat(var.config.security_group.ids, compact([module.ec2_instance.security_group_id])))
}

output "availability_zone" {
  description = "Availability zone of the EC2 instance."
  value       = module.ec2_instance.availability_zone
}
