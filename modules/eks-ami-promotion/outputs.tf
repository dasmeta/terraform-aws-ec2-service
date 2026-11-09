output "candidate_ami_id" {
  description = "Candidate image ID from the SSM parameter; validation is still required."
  value       = local.candidate.image_id
  sensitive   = true
}

output "candidate_release_version" {
  description = "Candidate EKS AMI release version; pass explicitly to the runbook after validation."
  value       = local.candidate.release_version
  sensitive   = true
}

output "promotion_document_arn" {
  description = "Manual approval-first runbook ARN. Terraform apply does not start the runbook."
  value       = aws_ssm_document.promote.arn
}

output "current_release_version" {
  description = "Current node-group AMI release version at plan time; record it before promotion for rollback planning."
  value       = data.aws_eks_node_group.current.release_version
}
