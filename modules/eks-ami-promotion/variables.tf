variable "name" {
  type        = string
  description = "Name prefix for the AMI promotion runbook."
  nullable    = false
  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be empty."
  }
}

variable "candidate" {
  type = object({
    parameter_name           = string # Public or private SSM parameter containing JSON with image_id and release_version.
    approved_release_version = string # Release version validated in nonproduction and pinned for this runbook.
  })
  description = "SSM parameter identifying a candidate EKS-optimized AMI release."
  nullable    = false
}

variable "promotion" {
  type = object({
    cluster_name               = string                 # Existing EKS cluster name.
    node_group_name            = string                 # Existing managed node group name.
    automation_role_arn        = string                 # Role allowed to describe and update this node group.
    notification_arn           = string                 # SNS topic for manual approval requests.
    approvers                  = list(string)           # Named IAM approver ARNs.
    approval_timeout           = optional(number, 3600) # Seconds before an unanswered request aborts.
    max_unavailable            = optional(number)       # Existing absolute node rollout limit, if configured.
    max_unavailable_percentage = optional(number)       # Existing percentage node rollout limit, if configured.
  })
  description = "Existing managed node group and approval settings; this module never starts a promotion automatically."
  nullable    = false
  validation {
    condition = (
      length(var.promotion.approvers) > 0 &&
      var.promotion.approval_timeout > 0 &&
      !(var.promotion.max_unavailable != null && var.promotion.max_unavailable_percentage != null) &&
      (var.promotion.max_unavailable == null ? true : var.promotion.max_unavailable > 0) &&
      (var.promotion.max_unavailable_percentage == null ? true : (var.promotion.max_unavailable_percentage > 0 && var.promotion.max_unavailable_percentage <= 100))
    )
    error_message = "Promotion requires named approvers, a positive timeout, and one valid rollout limit (absolute or percentage)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for the SSM runbook."
  default     = {}
}
