variable "ec2" {
  type = object({
    name                        = string
    ami                         = string
    vpc_id                      = string
    subnet_id                   = string
    instance_type               = optional(string, "t3.micro")
    key_name                    = optional(string)
    iam_instance_profile        = optional(string)
    user_data                   = optional(string)
    associate_public_ip_address = optional(bool, false)
    monitoring                  = optional(bool, true)
    root_volume = optional(object({
      size       = optional(number, 20)
      type       = optional(string, "gp3")
      kms_key_id = optional(string)
    }), {})
    security_group = optional(object({
      create = optional(bool, true)
      ids    = optional(list(string), [])
      ingress_rules = optional(map(object({
        port                         = number
        cidr_ipv4                    = optional(string)
        referenced_security_group_id = optional(string)
        description                  = optional(string)
      })), {})
    }), {})
  })
  default     = null
  description = "EC2 configuration; null disables instance creation. See modules/ec2."
}

variable "alb" {
  type = object({
    name                       = string
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
  default     = null
  description = "ALB configuration; null disables load balancer creation. See modules/alb."

  validation {
    condition     = var.alb == null ? true : length(distinct(var.alb.security_group.ids)) == length(var.alb.security_group.ids)
    error_message = "alb.security_group.ids must not contain duplicate IDs; each group is used as a backend ingress source."
  }
}

variable "target_groups" {
  type = map(object({
    name                    = optional(string)
    attach_created_instance = optional(bool, false)
    created_instance_port   = optional(number)
    port                    = number
    protocol                = optional(string, "HTTP")
    deregistration_delay    = optional(number, 300)
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
  description = "Target groups with existing targets and optional registration of the root-created instance."
  nullable    = false

  validation {
    condition     = var.alb != null || length(var.target_groups) == 0
    error_message = "target_groups requires an alb configuration."
  }
  validation {
    condition     = alltrue([for group in var.target_groups : !group.attach_created_instance || var.ec2 != null])
    error_message = "attach_created_instance requires an ec2 configuration."
  }
  validation {
    condition     = alltrue([for group in var.target_groups : !contains(keys(group.targets), "__created_instance")])
    error_message = "The target key __created_instance is reserved for the root-managed instance."
  }
  validation {
    condition     = alltrue([for group in var.target_groups : group.created_instance_port == null ? true : group.attach_created_instance && group.created_instance_port >= 1 && group.created_instance_port <= 65535 && floor(group.created_instance_port) == group.created_instance_port])
    error_message = "created_instance_port requires attach_created_instance=true and an integer port from 1 to 65535."
  }
  validation {
    condition     = anytrue([for group in var.target_groups : group.attach_created_instance]) ? try(var.ec2.vpc_id == var.alb.vpc_id, true) : true
    error_message = "The created instance and ALB must use the same VPC for instance target registration."
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
  description = "HTTP/HTTPS listeners forwarding to target group keys or redirecting to HTTPS."
  nullable    = false

  validation {
    condition     = var.alb != null || length(var.listeners) == 0
    error_message = "listeners requires an alb configuration."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to both components and connection rules."
  nullable    = false
}

variable "backend_ingress_rules" {
  type = map(object({
    security_group_id = string
    port              = number
    description       = optional(string)
  }))
  default     = {}
  description = "Explicit opt-in TCP ingress rules on existing backend security groups, sourced from the ALB security group(s). Does not manage the groups or instances themselves."
  nullable    = false

  validation {
    condition     = var.alb != null || length(var.backend_ingress_rules) == 0
    error_message = "backend_ingress_rules requires an alb configuration."
  }
  validation {
    condition     = alltrue([for rule in var.backend_ingress_rules : try(rule.port >= 1 && rule.port <= 65535 && floor(rule.port) == rule.port, false)])
    error_message = "Each backend ingress port must be an integer from 1 to 65535."
  }
  validation {
    condition     = alltrue([for rule in var.backend_ingress_rules : try(length(trimspace(rule.security_group_id)) > 0, false)])
    error_message = "Each backend ingress rule requires a nonempty security_group_id."
  }
  validation {
    condition     = length(distinct([for rule in var.backend_ingress_rules : jsonencode([rule.security_group_id, rule.port])])) == length(var.backend_ingress_rules)
    error_message = "Backend ingress rules must have unique security group and port pairs."
  }
}
