variable "name" {
  type        = string
  description = "Prefix for patch-management resources."
  nullable    = false
  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be empty."
  }
}

variable "patch_policy" {
  type = object({
    operating_system   = string                     # SSM operating-system identifier, for example AMAZON_LINUX_2023.
    classifications    = list(string)               # Approved patch classifications.
    severities         = optional(list(string), []) # Optional approved severities; empty selects all.
    approve_after_days = optional(number, 7)        # Days after release before automatic approval.
    rejected_patches   = optional(list(string), []) # Explicitly rejected patch IDs.
  })
  description = "OS patch baseline policy. Null uses AWS default baselines and creates no patch-group association."
  default     = null
  validation {
    condition     = var.patch_policy == null ? true : length(var.patch_policy.classifications) > 0 && var.patch_policy.approve_after_days >= 0
    error_message = "Provide classifications and a nonnegative approval delay."
  }
}

variable "nonproduction" {
  type = object({
    environment         = string                     # Value of the Environment tag on nonproduction instances.
    patch_group         = string                     # Value of the PatchGroup tag on nonproduction instances.
    scan_schedule       = string                     # Maintenance Window cron/rate expression for compliance scans.
    install_schedule    = optional(string)           # Maintenance Window cron/rate expression for patch installation; omit for scan-only.
    scan_only           = optional(bool, false)      # Create only a scan window and never schedule an Install task.
    target_instance_ids = optional(list(string), []) # EC2 instances to tag with Environment and PatchGroup for this target group.
    schedule_timezone   = string                     # IANA time zone for both schedules.
    duration            = optional(number, 3)        # Window length in hours.
    cutoff              = optional(number, 1)        # Hours before end when new tasks stop.
    max_concurrency     = optional(string, "1")      # Concurrent nodes per task.
    max_errors          = optional(string, "0")      # Failed nodes allowed per task.
    service_role_arn    = string                     # Maintenance Window service role ARN.
  })
  description = "Nonproduction target and schedule."
  nullable    = false
  validation {
    condition     = var.nonproduction.duration > var.nonproduction.cutoff && var.nonproduction.duration <= 24 && var.nonproduction.cutoff >= 0
    error_message = "duration must exceed nonnegative cutoff."
  }
  validation {
    condition     = var.nonproduction.scan_only ? true : var.nonproduction.install_schedule != null ? length(trimspace(var.nonproduction.install_schedule)) > 0 : false
    error_message = "install_schedule is required unless scan_only is true."
  }
  validation {
    condition     = length(var.nonproduction.target_instance_ids) == length(distinct(var.nonproduction.target_instance_ids))
    error_message = "target_instance_ids must not contain duplicates."
  }
}

variable "production" {
  type = object({
    environment         = string                 # Value of the Environment tag on production instances.
    patch_group         = string                 # Value of the PatchGroup tag on production instances.
    install_schedule    = string                 # Dedicated production window schedule.
    schedule_timezone   = string                 # IANA time zone for production schedule.
    duration            = optional(number, 3)    # Window length in hours.
    cutoff              = optional(number, 1)    # Hours before end when new tasks stop.
    max_concurrency     = optional(string, "1")  # Concurrent approved automations.
    max_errors          = optional(string, "0")  # Failed automations allowed.
    service_role_arn    = string                 # Maintenance Window service role ARN.
    automation_role_arn = string                 # Automation role allowed to run the patch command.
    notification_arn    = string                 # SNS topic ARN for approval notifications.
    approvers           = list(string)           # IAM user/role ARNs allowed to approve each execution.
    approval_timeout    = optional(number, 3600) # Seconds before unapproved execution aborts.
  })
  description = "Production approval and schedule; null disables production patching."
  default     = null
  validation {
    condition = var.production == null ? true : (
      length(var.production.approvers) > 0 &&
      var.production.duration > var.production.cutoff &&
      var.production.duration <= 24 &&
      var.production.cutoff >= 0 &&
      var.production.approval_timeout > 0 && var.production.approval_timeout <= 2592000 &&
      var.production.environment != var.nonproduction.environment &&
      var.production.patch_group != var.nonproduction.patch_group
    )
    error_message = "Production needs approvers, valid window limits, and distinct environment and patch group values."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags for created resources."
  default     = {}
}
