variable "name" {
  type        = string
  description = "Name of the instance and its managed security group."
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be empty."
  }
}

variable "config" {
  type = object({
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
  description = "Instance, encrypted root volume, and TCP security group configuration."
  nullable    = false

  validation {
    condition     = alltrue([for value in [var.config.ami, var.config.vpc_id, var.config.subnet_id] : try(length(trimspace(value)) > 0, false)])
    error_message = "config.ami, config.vpc_id, and config.subnet_id must be nonempty strings."
  }

  validation {
    condition     = var.config.root_volume.size > 0 && floor(var.config.root_volume.size) == var.config.root_volume.size
    error_message = "config.root_volume.size must be a positive integer in GiB."
  }

  validation {
    condition     = contains(["gp2", "gp3"], var.config.root_volume.type)
    error_message = "config.root_volume.type must be gp2 or gp3."
  }

  validation {
    condition     = alltrue([for rule in var.config.security_group.ingress_rules : try(rule.port >= 1 && rule.port <= 65535 && floor(rule.port) == rule.port, false)])
    error_message = "Every ingress port must be an integer from 1 through 65535."
  }

  validation {
    condition     = alltrue([for rule in var.config.security_group.ingress_rules : (rule.cidr_ipv4 != null) != (rule.referenced_security_group_id != null)])
    error_message = "Every ingress rule must specify exactly one of cidr_ipv4 or referenced_security_group_id."
  }

  validation {
    condition     = alltrue([for rule in var.config.security_group.ingress_rules : rule.cidr_ipv4 == null ? true : can(cidrnetmask(rule.cidr_ipv4))])
    error_message = "Every cidr_ipv4 must be a valid IPv4 CIDR."
  }

  validation {
    condition     = alltrue([for rule in var.config.security_group.ingress_rules : rule.referenced_security_group_id == null ? true : length(trimspace(rule.referenced_security_group_id)) > 0])
    error_message = "Referenced security group IDs must not be empty."
  }

  validation {
    condition     = var.config.security_group.create || (length(var.config.security_group.ids) > 0 && length(var.config.security_group.ingress_rules) == 0)
    error_message = "When security group creation is disabled, provide existing IDs and no ingress rules."
  }

  validation {
    condition = length(distinct([for rule in var.config.security_group.ingress_rules :
      jsonencode([rule.port, rule.cidr_ipv4, rule.referenced_security_group_id])
    ])) == length(var.config.security_group.ingress_rules)
    error_message = "Ingress rules must have unique source and port pairs, regardless of their keys."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the instance, root volume, and managed security group resources."
  nullable    = false
}
