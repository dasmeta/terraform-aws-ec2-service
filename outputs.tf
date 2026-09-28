output "instance_id" {
  description = "Created EC2 instance ID, or null when EC2 is disabled."
  value       = try(module.ec2[0].instance_id, null)
}

output "instance_arn" {
  description = "Created EC2 instance ARN, or null when EC2 is disabled."
  value       = try(module.ec2[0].instance_arn, null)
}

output "instance_private_ip" {
  description = "Created EC2 private IPv4 address, or null when EC2 is disabled."
  value       = try(module.ec2[0].private_ip, null)
}

output "instance_public_ip" {
  description = "Created EC2 public IPv4 address, if assigned."
  value       = try(module.ec2[0].public_ip, null)
}

output "instance_security_group_ids" {
  description = "Security groups attached to the created instance; empty when EC2 is disabled."
  value       = try(module.ec2[0].security_group_ids, [])
}

output "alb_arn" {
  description = "ALB ARN, or null when ALB is disabled."
  value       = try(module.alb[0].alb_arn, null)
}

output "alb_dns_name" {
  description = "ALB DNS name, or null when ALB is disabled."
  value       = try(module.alb[0].alb_dns_name, null)
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route53 aliases, or null when disabled."
  value       = try(module.alb[0].alb_zone_id, null)
}

output "alb_security_group_ids" {
  description = "Security groups attached to the ALB; empty when disabled."
  value       = try(module.alb[0].security_group_ids, [])
}

output "listener_arns" {
  description = "ALB listener ARNs by caller-provided key; empty when disabled."
  value       = try(module.alb[0].listener_arns, {})
}

output "target_group_arns" {
  description = "Target group ARNs by caller-provided key; empty when ALB is disabled."
  value       = try(module.alb[0].target_group_arns, {})
}
