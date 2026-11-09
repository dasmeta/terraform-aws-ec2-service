locals {
  environments = merge({ nonproduction = {
    environment       = var.nonproduction.environment
    patch_group       = var.nonproduction.patch_group
    service_role_arn  = var.nonproduction.service_role_arn
    schedule_timezone = var.nonproduction.schedule_timezone
    duration          = var.nonproduction.duration
    cutoff            = var.nonproduction.cutoff
    max_concurrency   = var.nonproduction.max_concurrency
    max_errors        = var.nonproduction.max_errors
    }
    }, var.production == null ? {} : { production = {
      environment       = var.production.environment
      patch_group       = var.production.patch_group
      service_role_arn  = var.production.service_role_arn
      schedule_timezone = var.production.schedule_timezone
      duration          = var.production.duration
      cutoff            = var.production.cutoff
      max_concurrency   = var.production.max_concurrency
      max_errors        = var.production.max_errors
  } })
  nonproduction_operations = var.nonproduction.scan_only ? { scan = "Scan" } : { scan = "Scan", install = "Install" }
  windows = merge({
    scan = merge(local.environments.nonproduction, { schedule = var.nonproduction.scan_schedule })
    }, var.nonproduction.scan_only ? {} : {
    install = merge(local.environments.nonproduction, { schedule = var.nonproduction.install_schedule })
    }, var.production == null ? {} : {
    production = merge(local.environments.production, { schedule = var.production.install_schedule })
  })
  nonproduction_target_tags = {
    for target in flatten([
      for instance_id in var.nonproduction.target_instance_ids : [
        { instance_id = instance_id, key = "Environment", value = var.nonproduction.environment },
        { instance_id = instance_id, key = "PatchGroup", value = var.nonproduction.patch_group }
      ]
    ]) : "${target.instance_id}:${target.key}" => target
  }
}

resource "aws_ssm_patch_baseline" "this" {
  count            = var.patch_policy == null ? 0 : 1
  name             = "${var.name}-baseline"
  operating_system = var.patch_policy.operating_system
  rejected_patches = var.patch_policy.rejected_patches
  approval_rule {
    approve_after_days = var.patch_policy.approve_after_days
    patch_filter {
      key    = "CLASSIFICATION"
      values = var.patch_policy.classifications
    }
    dynamic "patch_filter" {
      for_each = length(var.patch_policy.severities) == 0 ? [] : [var.patch_policy.severities]
      content {
        key    = "SEVERITY"
        values = patch_filter.value
      }
    }
  }
  tags = var.tags
}

resource "aws_ssm_patch_group" "this" {
  for_each    = var.patch_policy == null ? {} : local.environments
  baseline_id = aws_ssm_patch_baseline.this[0].id
  patch_group = each.value.patch_group
}

resource "aws_ec2_tag" "nonproduction_targets" {
  for_each    = local.nonproduction_target_tags
  resource_id = each.value.instance_id
  key         = each.value.key
  value       = each.value.value
}

resource "aws_resourcegroups_group" "targets" {
  for_each = local.environments
  name     = "${var.name}-${each.key}-patch-targets"
  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::EC2::Instance"]
      TagFilters = [
        { Key = "Environment", Values = [each.value.environment] },
        { Key = "PatchGroup", Values = [each.value.patch_group] }
      ]
    })
  }
  tags = var.tags
}

resource "aws_ssm_maintenance_window" "this" {
  for_each                   = local.windows
  name                       = "${var.name}-${each.key}"
  schedule                   = each.value.schedule
  schedule_timezone          = each.value.schedule_timezone
  duration                   = each.value.duration
  cutoff                     = each.value.cutoff
  allow_unassociated_targets = false
  tags                       = var.tags
}

resource "aws_ssm_maintenance_window_target" "this" {
  for_each      = local.windows
  window_id     = aws_ssm_maintenance_window.this[each.key].id
  resource_type = "RESOURCE_GROUP"
  targets {
    key    = "resource-groups:Name"
    values = [aws_resourcegroups_group.targets[each.key == "production" ? "production" : "nonproduction"].name]
  }
  depends_on = [aws_ec2_tag.nonproduction_targets]
}

resource "aws_ssm_maintenance_window_task" "nonproduction" {
  for_each         = local.nonproduction_operations
  window_id        = aws_ssm_maintenance_window.this[each.key].id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  service_role_arn = var.nonproduction.service_role_arn
  max_concurrency  = var.nonproduction.max_concurrency
  max_errors       = var.nonproduction.max_errors
  priority         = 1
  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this[each.key].id]
  }
  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = [each.value]
      }
    }
  }
}

resource "aws_ssm_document" "approved_install" {
  count           = var.production == null ? 0 : 1
  name            = "${var.name}-approved-install"
  document_type   = "Automation"
  document_format = "YAML"
  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Approve a production EC2 patch before installation"
    targetType    = "/AWS::EC2::Instance"
    assumeRole    = var.production.automation_role_arn
    parameters = {
      InstanceId        = { type = "String", description = "Production EC2 instance ID" }
      WindowId          = { type = "String", description = "Current maintenance window ID" }
      WindowExecutionId = { type = "String", description = "Current maintenance window execution ID" }
    }
    mainSteps = [
      {
        name           = "approveInstallation"
        action         = "aws:approve"
        timeoutSeconds = var.production.approval_timeout
        onFailure      = "Abort"
        inputs = {
          NotificationArn      = var.production.notification_arn
          Message              = "Approve production patch installation for {{ InstanceId }}"
          MinRequiredApprovals = 1
          Approvers            = var.production.approvers
        }
      },
      {
        name           = "verifyWindowOpen"
        action         = "aws:executeScript"
        timeoutSeconds = 60
        onFailure      = "Abort"
        inputs = {
          Runtime = "python3.11"
          Handler = "check_window"
          InputPayload = {
            window_id           = "{{ WindowId }}"
            window_execution_id = "{{ WindowExecutionId }}"
          }
          Script = <<-PY
            def check_window(events, context):
                import boto3
                from datetime import datetime, timedelta, timezone

                ssm = boto3.client("ssm")
                execution = ssm.get_maintenance_window_execution(WindowExecutionId=events["window_execution_id"])
                window = ssm.get_maintenance_window(WindowId=events["window_id"])
                latest_start = execution["StartTime"] + timedelta(hours=window["Duration"] - window["Cutoff"])
                if execution["Status"] != "IN_PROGRESS" or datetime.now(timezone.utc) >= latest_start - timedelta(minutes=5):
                    raise RuntimeError("Production patch window is closed or near cutoff")
                return {"allowed": True}
          PY
        }
      },
      {
        name      = "verifyProductionTarget"
        action    = "aws:assertAwsResourceProperty"
        onFailure = "Abort"
        inputs = {
          Service     = "ec2"
          Api         = "DescribeInstances"
          InstanceIds = ["{{ InstanceId }}"]
          Filters = [
            { Name = "tag:Environment", Values = [var.production.environment] },
            { Name = "tag:PatchGroup", Values = [var.production.patch_group] }
          ]
          PropertySelector = "$.Reservations[0].Instances[0].InstanceId"
          DesiredValues    = ["{{ InstanceId }}"]
        }
      },
      {
        name      = "installPatches"
        action    = "aws:runCommand"
        onFailure = "Abort"
        inputs = {
          DocumentName = "AWS-RunPatchBaseline"
          InstanceIds  = ["{{ InstanceId }}"]
          Parameters   = { Operation = ["Install"] }
        }
      }
    ]
  })
  tags = var.tags
}

resource "aws_ssm_maintenance_window_task" "production" {
  count            = var.production == null ? 0 : 1
  window_id        = aws_ssm_maintenance_window.this["production"].id
  task_type        = "AUTOMATION"
  task_arn         = aws_ssm_document.approved_install[0].arn
  service_role_arn = var.production.service_role_arn
  max_concurrency  = var.production.max_concurrency
  max_errors       = var.production.max_errors
  priority         = 1
  cutoff_behavior  = "CANCEL_TASK"
  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this["production"].id]
  }
  task_invocation_parameters {
    automation_parameters {
      document_version = "$DEFAULT"
      parameter {
        name   = "InstanceId"
        values = ["{{RESOURCE_ID}}"]
      }
      parameter {
        name   = "WindowId"
        values = ["{{WINDOW_ID}}"]
      }
      parameter {
        name   = "WindowExecutionId"
        values = ["{{WINDOW_EXECUTION_ID}}"]
      }
    }
  }
}
