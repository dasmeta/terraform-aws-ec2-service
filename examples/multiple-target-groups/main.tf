module "alb" {
  source = "../../modules/alb"

  name = "example-multiple-targets"
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
    api = {
      name         = "example-api"
      port         = 9000
      targets      = { for key, id in var.instance_ids : key => { instance_id = id } }
      health_check = { path = "/ready", port = "9090" }
    }
  }
  listeners = {
    http = { port = 80, redirect_to_https = true }
    https = {
      port             = 443
      protocol         = "HTTPS"
      certificate_arn  = var.certificate_arn
      target_group_key = "web"
    }
    api = {
      port             = 8443
      protocol         = "HTTPS"
      certificate_arn  = var.certificate_arn
      target_group_key = "api"
    }
  }
  tags = { Environment = "example" }
}

output "target_group_arns" {
  description = "Web and API group ARNs; the same instances serve different ports."
  value       = module.alb.target_group_arns
}

output "alb_security_group_id" {
  description = "Allow this source in existing backend groups on 8080, 9000 and 9090."
  value       = module.alb.security_group_id
}
