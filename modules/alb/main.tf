module "this" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.1"

  name                       = var.name
  load_balancer_type         = "application"
  vpc_id                     = var.config.vpc_id
  subnets                    = var.config.subnet_ids
  internal                   = var.config.internal
  enable_deletion_protection = var.config.enable_deletion_protection
  idle_timeout               = var.config.idle_timeout

  listeners                           = local.listeners
  target_groups                       = local.target_groups
  additional_target_group_attachments = local.target_group_attachments

  create_security_group        = var.config.security_group.create
  security_groups              = var.config.security_group.ids
  security_group_ingress_rules = local.ingress_rules
  security_group_name          = var.config.security_group.name
  security_group_description   = var.config.security_group.description
  security_group_egress_rules  = local.egress_rules

  tags = var.tags
}
