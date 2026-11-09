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
