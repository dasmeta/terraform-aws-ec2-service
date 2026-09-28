variable "name" {
  type        = string
  description = "ALB name (1-32 alphanumeric characters or hyphens, not starting with internal-)."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 1-32 alphanumeric/hyphen characters, without leading/trailing hyphens or the internal- prefix."
  }
}

variable "config" {
  type = object({
    vpc_id                     = string
    subnet_ids                 = list(string)
    internal                   = optional(bool, true)
    enable_deletion_protection = optional(bool, true)
    idle_timeout               = optional(number, 60)
    security_group = optional(object({
      create              = optional(bool, true)
      ids                 = optional(list(string), [])
      allowed_cidr_blocks = optional(list(string), [])
      name                = optional(string)
      description         = optional(string)
      egress_rules = optional(map(object({
        port                         = number
        cidr_ipv4                    = optional(string)
        referenced_security_group_id = optional(string)
        description                  = optional(string)
      })))
    }), {})
  })
  description = "ALB network and security settings. Supply IPv4 CIDRs explicitly to permit listener ingress."
  nullable    = false

  validation {
    condition     = length(distinct(var.config.subnet_ids)) >= 2
    error_message = "config.subnet_ids must contain at least two distinct subnets; choose subnets in different availability zones."
  }
  validation {
    condition     = var.config.security_group.create || length(var.config.security_group.ids) > 0
    error_message = "Supply security_group.ids when security_group.create is false."
  }
  validation {
    condition     = var.config.security_group.create || length(var.config.security_group.allowed_cidr_blocks) == 0
    error_message = "allowed_cidr_blocks requires a module-created security group; manage existing group rules externally."
  }
  validation {
    condition     = alltrue([for cidr in var.config.security_group.allowed_cidr_blocks : can(cidrnetmask(cidr))])
    error_message = "allowed_cidr_blocks must contain valid IPv4 CIDRs."
  }
  validation {
    condition     = var.config.idle_timeout >= 1 && var.config.idle_timeout <= 4000 && floor(var.config.idle_timeout) == var.config.idle_timeout
    error_message = "idle_timeout must be an integer from 1 to 4000 seconds."
  }

  validation {
    condition     = var.config.security_group.create || var.config.security_group.egress_rules == null
    error_message = "egress_rules requires a module-created ALB security group; manage supplied ALB group rules externally."
  }
  validation {
    condition     = alltrue([for rule in coalesce(var.config.security_group.egress_rules, {}) : try(rule.port >= 1 && rule.port <= 65535 && floor(rule.port) == rule.port, false)])
    error_message = "Each egress port must be an integer from 1 to 65535."
  }
  validation {
    condition     = alltrue([for rule in coalesce(var.config.security_group.egress_rules, {}) : (rule.cidr_ipv4 != null) != (rule.referenced_security_group_id != null)])
    error_message = "Each egress rule must specify exactly one of cidr_ipv4 or referenced_security_group_id."
  }
  validation {
    condition     = alltrue([for rule in coalesce(var.config.security_group.egress_rules, {}) : rule.cidr_ipv4 == null ? true : can(cidrnetmask(rule.cidr_ipv4))])
    error_message = "Egress cidr_ipv4 values must be valid IPv4 CIDRs."
  }
  validation {
    condition     = alltrue([for rule in coalesce(var.config.security_group.egress_rules, {}) : rule.referenced_security_group_id == null ? true : length(trimspace(rule.referenced_security_group_id)) > 0])
    error_message = "Egress referenced_security_group_id values must not be empty."
  }
  validation {
    condition = length(distinct([for rule in coalesce(var.config.security_group.egress_rules, {}) :
      jsonencode([rule.port, rule.cidr_ipv4, rule.referenced_security_group_id])
    ])) == length(coalesce(var.config.security_group.egress_rules, {}))
    error_message = "Egress rules must have unique destination and port pairs."
  }
}

variable "target_groups" {
  type = map(object({
    name                 = optional(string)
    port                 = number
    protocol             = optional(string, "HTTP")
    deregistration_delay = optional(number, 300)
    health_check = optional(object({
      path                = optional(string, "/")
      port                = optional(string, "traffic-port")
      protocol            = optional(string, "HTTP")
      matcher             = optional(string, "200-399")
      interval            = optional(number, 30)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
    targets = optional(map(object({
      instance_id = string
      port        = optional(number)
    })), {})
  }))
  default     = {}
  description = "Named instance target groups and keyed targets. Empty groups are supported; target port defaults to group port."
  nullable    = false

  validation {
    condition     = alltrue([for group in var.target_groups : group.name == null ? true : can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", group.name))])
    error_message = "Target group names must be 1-32 alphanumeric/hyphen characters without leading or trailing hyphens; omit name to use the ALB name."
  }
  validation {
    condition     = length(distinct([for group in var.target_groups : group.name == null ? var.name : group.name])) == length(var.target_groups)
    error_message = "Target group names must be unique. An omitted name uses the ALB name, so give other groups distinct explicit names."
  }

  validation {
    condition     = alltrue([for group in var.target_groups : contains(["HTTP", "HTTPS"], group.protocol) && contains(["HTTP", "HTTPS"], group.health_check.protocol)])
    error_message = "Target group and health check protocols must be HTTP or HTTPS."
  }
  validation {
    condition = alltrue(flatten([for group in var.target_groups : concat(
      [group.port >= 1 && group.port <= 65535 && floor(group.port) == group.port],
      [for target in group.targets : target.port == null ? true : target.port >= 1 && target.port <= 65535 && floor(target.port) == target.port]
    )]))
    error_message = "Target group and target ports must be integers from 1 to 65535."
  }
  validation {
    condition = alltrue([for group in var.target_groups : group.health_check.port == "traffic-port" ? true : try(
      tonumber(group.health_check.port) >= 1 && tonumber(group.health_check.port) <= 65535 && floor(tonumber(group.health_check.port)) == tonumber(group.health_check.port), false
    )])
    error_message = "Health check port must be traffic-port or an integer from 1 to 65535."
  }
  validation {
    condition     = alltrue(flatten([for group in var.target_groups : [for target in group.targets : try(length(trimspace(target.instance_id)) > 0, false)]]))
    error_message = "Each target must have a nonempty instance_id."
  }
  validation {
    condition = alltrue([for group in var.target_groups :
      length(distinct([for target in group.targets : jsonencode([target.instance_id, coalesce(target.port, group.port)])])) == length(group.targets)
    ])
    error_message = "Each instance and effective port pair must be unique within a target group."
  }
  validation {
    condition = alltrue([for group in var.target_groups :
      group.deregistration_delay >= 0 && group.deregistration_delay <= 3600 && floor(group.deregistration_delay) == group.deregistration_delay &&
      startswith(group.health_check.path, "/") &&
      group.health_check.interval >= 5 && group.health_check.interval <= 300 && floor(group.health_check.interval) == group.health_check.interval &&
      group.health_check.timeout >= 2 && group.health_check.timeout <= 120 && floor(group.health_check.timeout) == group.health_check.timeout && group.health_check.timeout < group.health_check.interval &&
      group.health_check.healthy_threshold >= 2 && group.health_check.healthy_threshold <= 10 && floor(group.health_check.healthy_threshold) == group.health_check.healthy_threshold &&
      group.health_check.unhealthy_threshold >= 2 && group.health_check.unhealthy_threshold <= 10 && floor(group.health_check.unhealthy_threshold) == group.health_check.unhealthy_threshold
    ])
    error_message = "Health checks require a / path, interval 5-300, timeout 2-120 less than interval, thresholds 2-10; deregistration_delay must be 0-3600. Numeric values must be integers."
  }
}

variable "listeners" {
  type = map(object({
    port              = number
    protocol          = optional(string, "HTTP")
    target_group_key  = optional(string)
    certificate_arn   = optional(string)
    ssl_policy        = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    redirect_to_https = optional(bool, false)
    redirect_port     = optional(number, 443)
  }))
  default     = {}
  description = "Named HTTP/HTTPS listeners. Choose target_group_key or an HTTP-to-HTTPS redirect with a corresponding HTTPS listener."
  nullable    = false

  validation {
    condition     = alltrue([for listener in var.listeners : contains(["HTTP", "HTTPS"], listener.protocol) && listener.port >= 1 && listener.port <= 65535 && floor(listener.port) == listener.port])
    error_message = "Listeners must use HTTP or HTTPS and integer ports from 1 to 65535."
  }
  validation {
    condition     = length(distinct([for listener in var.listeners : listener.port])) == length(var.listeners)
    error_message = "Listener ports must be unique."
  }
  validation {
    condition     = alltrue([for listener in var.listeners : listener.protocol == "HTTPS" ? try(length(trimspace(listener.certificate_arn)) > 0, false) : listener.certificate_arn == null])
    error_message = "HTTPS listeners require a certificate_arn; HTTP listeners must not set one."
  }
  validation {
    condition = alltrue([for listener in var.listeners : listener.redirect_to_https ? (
      listener.protocol == "HTTP" && listener.target_group_key == null && contains([for destination in var.listeners : destination.port if destination.protocol == "HTTPS"], listener.redirect_port)
      ) : try(contains(keys(var.target_groups), listener.target_group_key), false)
    ])
    error_message = "Each listener must forward to an existing target_group_key or redirect HTTP to a configured HTTPS listener port, without a target_group_key."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to ALB resources."
  nullable    = false
}
