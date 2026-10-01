output "alb_arn" {
  description = "ARN of the application load balancer."
  value       = module.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer."
  value       = module.this.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID for a Route53 alias."
  value       = module.this.zone_id
}

output "security_group_id" {
  description = "Module-created ALB security group ID, or null when disabled."
  value       = module.this.security_group_id
}

output "security_group_ids" {
  description = "Security group IDs attached to the ALB."
  value       = concat(var.config.security_group.create ? [module.this.security_group_id] : [], var.config.security_group.ids)
}

output "listener_arns" {
  description = "Listener ARNs by caller-provided listener key."
  value       = { for key, listener in module.this.listeners : key => listener.arn }
}

output "target_group_arns" {
  description = "Target group ARNs by caller-provided group key."
  value       = { for key, group in module.this.target_groups : key => group.arn }
}
