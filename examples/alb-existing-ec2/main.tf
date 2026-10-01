module "alb" {
  source = "../../modules/alb"

  name = "example-existing-ec2"
  config = {
    vpc_id         = var.vpc_id
    subnet_ids     = var.alb_subnet_ids
    security_group = { allowed_cidr_blocks = var.allowed_cidr_blocks }
  }
  target_groups = {
    web = {
      port         = 8080
      targets      = { for key, id in var.instance_ids : key => { instance_id = id } }
      health_check = { path = "/health" }
    }
  }
  listeners = { http = { port = 80, target_group_key = "web" } }
  tags      = { Environment = "example" }
}

output "alb_dns_name" {
  description = "ALB endpoint. Existing instance groups must allow traffic from the ALB."
  value       = module.alb.alb_dns_name
}

output "alb_security_group_id" {
  description = "Source group to permit in the existing instance security groups."
  value       = module.alb.security_group_id
}
