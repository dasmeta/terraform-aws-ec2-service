variable "candidate_parameter_name" {
  type        = string
  description = "Pinned SSM parameter JSON containing image_id and release_version."
}
variable "approved_release_version" {
  type        = string
  description = "Release version validated in nonproduction."
}
variable "promotion" {
  type = object({
    cluster_name               = string
    node_group_name            = string
    automation_role_arn        = string
    notification_arn           = string
    approvers                  = list(string)
    max_unavailable            = optional(number)
    max_unavailable_percentage = optional(number)
  })
  description = "Existing node group and named production approval configuration."
}

module "eks_ami" {
  source = "../../modules/eks-ami-promotion"
  name   = "example-eks"
  candidate = {
    parameter_name           = var.candidate_parameter_name
    approved_release_version = var.approved_release_version
  }
  promotion = var.promotion
}

# Merge module.eks_ami.notification_policy_statement into the approval topic
# policy. Start a pinned numeric document version with ApprovalReference only
# after validating the release, PDBs, spare capacity and replacement recovery.
# Final health approval requires Ready nodes, healthy pods and application checks.
