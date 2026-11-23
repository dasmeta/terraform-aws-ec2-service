output "candidate_ami_id" {
  description = "Candidate image ID from the SSM parameter; validation is still required."
  value       = local.candidate.image_id
  sensitive   = true
}

output "candidate_release_version" {
  description = "Candidate EKS AMI release version; pin as approved_release_version after validation."
  value       = local.candidate.release_version
  sensitive   = true
}

output "promotion_document_arn" {
  description = "Manual approval-first runbook ARN. Terraform apply does not start the runbook."
  value       = aws_ssm_document.promote.arn
}

output "current_release_version" {
  description = "Current node-group AMI release version at plan time; record it before promotion for replacement-group recovery."
  value       = data.aws_eks_node_group.current.release_version
}

output "notification_policy_statement" {
  description = "Merge into the existing SNS topic policy; do not replace its other statements. The topic and any KMS key must permit EventBridge publication."
  value = {
    Sid       = "${replace(var.name, "-", "")}EksAutomationEvents"
    Effect    = "Allow"
    Principal = { Service = "events.amazonaws.com" }
    Action    = "sns:Publish"
    Resource  = var.promotion.notification_arn
    Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.execution_status.arn } }
  }
}
