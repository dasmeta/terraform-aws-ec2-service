output "patch_baseline_id" {
  description = "Patch baseline identifier."
  value       = aws_ssm_patch_baseline.this.id
}

output "maintenance_window_ids" {
  description = "Scan, nonproduction install, and optional production window IDs."
  value       = { for key, window in aws_ssm_maintenance_window.this : key => window.id }
}

output "production_approval_document_arn" {
  description = "Approval-first production installation Automation document ARN, or null."
  value       = try(aws_ssm_document.approved_install[0].arn, null)
}
