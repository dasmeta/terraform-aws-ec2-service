locals {
  target_groups = {
    for key, group in var.target_groups : key => merge(group, {
      targets = merge(group.targets, group.attach_created_instance && var.ec2 != null ? {
        __created_instance = {
          instance_id = module.ec2[0].instance_id
          port        = coalesce(group.created_instance_port, group.port)
        }
      } : {})
    })
  }

  managed_target_groups = { for key, group in var.target_groups : key => group if group.attach_created_instance }

  # The keys depend on configured ports, never on generated resource IDs.
  managed_ports = toset(flatten([for group in local.managed_target_groups : [
    tostring(coalesce(group.created_instance_port, group.port)),
    group.health_check.port == "traffic-port" ? tostring(coalesce(group.created_instance_port, group.port)) : try(tostring(tonumber(group.health_check.port)), "0")
  ]]))

  alb_source_security_groups = var.alb == null ? {} : (var.alb.security_group.create ? {
    managed = module.alb[0].security_group_id
    } : {
    for index, id in var.alb.security_group.ids : "existing-${index}" => id
  })

  alb_ingress_rules = try(var.ec2.security_group.create, false) && var.alb != null ? merge({}, [
    for port in local.managed_ports : {
      for source_key, id in local.alb_source_security_groups : jsonencode([port, source_key]) => {
        port              = tonumber(port)
        security_group_id = id
      }
    }
  ]...) : {}
}

locals {
  backend_ingress_rules = merge({}, [for key, rule in var.backend_ingress_rules : {
    for source_key, source_id in local.alb_source_security_groups : jsonencode([key, source_key]) => {
      security_group_id = rule.security_group_id
      source_group_id   = source_id
      port              = rule.port
      description       = coalesce(rule.description, "ALB access to backend on TCP ${rule.port}")
    }
  }]...)
}
