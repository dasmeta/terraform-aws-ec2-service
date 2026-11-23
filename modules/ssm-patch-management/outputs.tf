output "patch_baseline_id" {
  description = "Created patch baseline identifier, or null when AWS defaults are used."
  value       = try(aws_ssm_patch_baseline.this[0].id, null)
}

output "maintenance_window_ids" {
  description = "Created scan, optional nonproduction install, and optional production window IDs."
  value       = { for key, window in aws_ssm_maintenance_window.this : key => window.id }
}

output "production_approval_document_arn" {
  description = "Approval-first production installation Automation document ARN, or null."
  value       = try(aws_ssm_document.approved_install[0].arn, null)
}

output "notification_policy_statement" {
  description = "Merge into the existing SNS topic policy; do not replace its other statements. The topic and any KMS key must permit EventBridge publication."
  value = var.production == null ? null : {
    Sid       = "${replace(var.name, "-", "")}PatchAutomationEvents"
    Effect    = "Allow"
    Principal = { Service = "events.amazonaws.com" }
    Action    = "sns:Publish"
    Resource  = try(var.production.notification_arn, null)
    Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.execution_status[0].arn } }
  }
}

output "nonproduction_notification_rule_arn" {
  description = "Grant this rule ARN events.amazonaws.com sns:Publish in the existing nonproduction topic policy."
  value       = try(aws_cloudwatch_event_rule.nonproduction_status[0].arn, null)
}
