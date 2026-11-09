variable "maintenance_window_role_arn" {
  type        = string
  description = "Existing SSM Maintenance Window service role ARN."
}

module "patching" {
  source = "../../modules/ssm-patch-management"
  name   = "example-linux"

  patch_policy = {
    operating_system   = "AMAZON_LINUX_2023"
    classifications    = ["Security"]
    approve_after_days = 7
  }
  nonproduction = {
    environment       = "development"
    patch_group       = "example-dev-linux"
    scan_schedule     = "cron(0 1 ? * SUN *)"
    install_schedule  = "cron(0 2 ? * SUN *)"
    schedule_timezone = "UTC"
    service_role_arn  = var.maintenance_window_role_arn
  }
  # Add production only after the window, roles, SNS topic, and approvers are approved.
}
