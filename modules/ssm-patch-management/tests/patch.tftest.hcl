mock_provider "aws" {}

variables {
  name = "example"
  patch_policy = {
    operating_system = "AMAZON_LINUX_2023"
    classifications  = ["Security"]
  }
  nonproduction = {
    environment       = "development"
    patch_group       = "dev-linux"
    scan_schedule     = "cron(0 1 ? * SUN *)"
    install_schedule  = "cron(0 2 ? * SUN *)"
    schedule_timezone = "UTC"
    service_role_arn  = "arn:aws:iam::123456789012:role/ssm-window"
  }
  production = {
    environment         = "production"
    patch_group         = "prod-linux"
    install_schedule    = "cron(0 2 ? * SUN *)"
    schedule_timezone   = "UTC"
    service_role_arn    = "arn:aws:iam::123456789012:role/ssm-window"
    automation_role_arn = "arn:aws:iam::123456789012:role/ssm-automation"
    notification_arn    = "arn:aws:sns:us-east-1:123456789012:AutomationApproval"
    approvers           = ["arn:aws:iam::123456789012:role/PatchApprover"]
  }
}

run "production_requires_approval" {
  command = plan
  assert {
    condition     = aws_ssm_maintenance_window_task.production[0].task_type == "AUTOMATION"
    error_message = "Production must schedule Automation."
  }
  assert {
    condition     = yamldecode(aws_ssm_document.approved_install[0].content).mainSteps[0].action == "aws:approve"
    error_message = "Approval must be the first production step."
  }
  assert {
    condition     = yamldecode(aws_ssm_document.approved_install[0].content).mainSteps[1].action == "aws:executeScript" && yamldecode(aws_ssm_document.approved_install[0].content).mainSteps[2].action == "aws:assertAwsResourceProperty" && yamldecode(aws_ssm_document.approved_install[0].content).mainSteps[3].action == "aws:runCommand"
    error_message = "Window and target verification must precede patch installation."
  }
  assert {
    condition     = length(aws_ssm_maintenance_window_task.nonproduction) == 2
    error_message = "Nonproduction requires independent scan and install tasks."
  }
  assert {
    condition     = length(jsondecode(aws_resourcegroups_group.targets["nonproduction"].resource_query[0].query).TagFilters) == 2
    error_message = "Targets must require both environment and patch-group tags."
  }
}

run "production_disabled_by_default" {
  command = plan
  variables {
    production = null
  }
  assert {
    condition     = length(aws_ssm_maintenance_window_task.production) == 0
    error_message = "No production task may exist without explicit configuration."
  }
}

run "scan_only_uses_default_baselines_and_exact_instances" {
  command = plan
  variables {
    patch_policy = null
    production   = null
    nonproduction = {
      environment         = "dev"
      patch_group         = "sela-dev-ec2-test"
      scan_schedule       = "cron(0 1 ? * SUN *)"
      scan_only           = true
      target_instance_ids = ["i-04cb67458bffa5472", "i-024dc0b7d614d44a4"]
      schedule_timezone   = "UTC"
      service_role_arn    = "arn:aws:iam::123456789012:role/ssm-window"
    }
  }
  assert {
    condition     = length(aws_ssm_patch_baseline.this) == 0 && length(aws_ssm_patch_group.this) == 0
    error_message = "Scan-only testing must use AWS default OS baselines."
  }
  assert {
    condition     = length(aws_ssm_maintenance_window.this) == 1 && length(aws_ssm_maintenance_window_task.nonproduction) == 1 && alltrue([for p in aws_ssm_maintenance_window_task.nonproduction["scan"].task_invocation_parameters[0].run_command_parameters[0].parameter : p.values[0] == "Scan"])
    error_message = "Scan-only testing must create one Scan window and no Install task."
  }
  assert {
    condition     = length(aws_ec2_tag.nonproduction_targets) == 4
    error_message = "Both explicit instances must receive Environment and PatchGroup tags."
  }
}
