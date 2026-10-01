locals {
  egress_rules = var.config.security_group.egress_rules == null ? {
    ipv4 = {
      cidr_ipv4                    = "0.0.0.0/0"
      referenced_security_group_id = null
      from_port                    = null
      to_port                      = null
      ip_protocol                  = "-1"
      description                  = "Allow outbound IPv4 traffic to targets"
    }
    } : {
    for key, rule in var.config.security_group.egress_rules : key => {
      cidr_ipv4                    = rule.cidr_ipv4
      referenced_security_group_id = rule.referenced_security_group_id
      from_port                    = rule.port
      to_port                      = rule.port
      ip_protocol                  = "tcp"
      description                  = rule.description
    }
  }

  target_group_names = {
    for key, group in var.target_groups : key => group.name == null ? var.name : group.name
  }

  target_groups = {
    for key, group in var.target_groups : key => {
      name                 = local.target_group_names[key]
      port                 = group.port
      protocol             = group.protocol
      target_type          = "instance"
      create_attachment    = false
      deregistration_delay = group.deregistration_delay
      health_check         = merge(group.health_check, { enabled = true })
      tags                 = { Name = local.target_group_names[key] }
    }
  }

  target_group_attachments = merge({}, [for group_key, group in var.target_groups : {
    for target_key, target in group.targets : jsonencode([group_key, target_key]) => {
      target_group_key = group_key
      target_id        = target.instance_id
      target_type      = "instance"
      # Upstream additional attachments otherwise default to 80, not the group port.
      port = coalesce(target.port, group.port)
    }
  }]...)

  listeners = {
    for key, listener in var.listeners : key => {
      port            = listener.port
      protocol        = listener.protocol
      certificate_arn = listener.certificate_arn
      ssl_policy      = listener.protocol == "HTTPS" ? listener.ssl_policy : null
      forward         = listener.redirect_to_https ? null : { target_group_key = listener.target_group_key }
      redirect = listener.redirect_to_https ? {
        port        = tostring(listener.redirect_port)
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      } : null
    }
  }

  ingress_rules = merge({}, [for key, listener in var.listeners : {
    for cidr in toset(var.config.security_group.allowed_cidr_blocks) : jsonencode([key, cidr]) => {
      cidr_ipv4   = cidr
      from_port   = listener.port
      to_port     = listener.port
      ip_protocol = "tcp"
      description = "${listener.protocol} listener ${key}"
    }
  }]...)
}
