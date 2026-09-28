module "service" {
  source = "../.."

  ec2 = {
    name      = "example-compute"
    ami       = var.ami_id
    vpc_id    = var.vpc_id
    subnet_id = var.instance_subnet_id
    user_data = var.user_data
  }
  alb = {
    name           = "example-service"
    vpc_id         = var.vpc_id
    subnet_ids     = var.alb_subnet_ids
    security_group = { allowed_cidr_blocks = var.allowed_cidr_blocks }
  }
  target_groups = {
    web = {
      port                    = 8080
      attach_created_instance = true
      health_check            = { path = "/health" }
    }
  }
  listeners = { http = { port = 80, target_group_key = "web" } }
  tags      = { Environment = "example" }
}

output "instance_id" {
  description = "Created EC2 instance ID."
  value       = module.service.instance_id
}

output "alb_dns_name" {
  description = "Service endpoint."
  value       = module.service.alb_dns_name
}
