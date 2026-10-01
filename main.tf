module "ec2" {
  count = var.ec2 == null ? 0 : 1

  source = "./modules/ec2"

  name   = var.ec2.name
  config = var.ec2
  tags   = var.tags
}

module "alb" {
  count = var.alb == null ? 0 : 1

  source = "./modules/alb"

  name          = var.alb.name
  config        = var.alb
  target_groups = local.target_groups
  listeners     = var.listeners
  tags          = var.tags
}

# Connection rules are separate from both modules to avoid an EC2/ALB cycle.
# Automatic connection rules only modify the module-created EC2 security group.
resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = local.alb_ingress_rules

  security_group_id            = module.ec2[0].security_group_id
  referenced_security_group_id = each.value.security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  description                  = "ALB access to ${var.ec2.name} on TCP ${each.value.port}"

  tags = var.tags

  lifecycle {
    precondition {
      condition = alltrue([for rule in var.ec2.security_group.ingress_rules :
        rule.referenced_security_group_id == null ? true : rule.port != each.value.port || rule.referenced_security_group_id != each.value.security_group_id
      ])
      error_message = "An ec2.security_group.ingress_rules entry duplicates automatic ALB ingress. Remove the explicit rule for this ALB source group and port."
    }
  }
}

# Opt-in additive rules only: the existing SG and its instances stay externally owned.
resource "aws_vpc_security_group_ingress_rule" "backend" {
  for_each = local.backend_ingress_rules

  security_group_id            = each.value.security_group_id
  referenced_security_group_id = each.value.source_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  description                  = each.value.description

  tags = var.tags

  lifecycle {
    precondition {
      condition = !try(var.ec2.security_group.create, false) ? true : (
        each.value.security_group_id != module.ec2[0].security_group_id || (
          !contains(local.managed_ports, tostring(each.value.port)) &&
          alltrue([for rule in var.ec2.security_group.ingress_rules :
            rule.referenced_security_group_id == null ? true : rule.port != each.value.port || rule.referenced_security_group_id != each.value.source_group_id
          ])
        )
      )
      error_message = "backend_ingress_rules duplicates ingress already managed for the created EC2. Remove the duplicate explicit backend rule."
    }
  }
}
