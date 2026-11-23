data "aws_ssm_parameter" "candidate" {
  name = var.candidate.parameter_name
}

data "aws_eks_node_group" "current" {
  cluster_name    = var.promotion.cluster_name
  node_group_name = var.promotion.node_group_name
}

locals {
  candidate            = jsondecode(data.aws_ssm_parameter.candidate.value)
  use_percentage_limit = var.promotion.max_unavailable_percentage != null
  rollout_limit        = local.use_percentage_limit ? var.promotion.max_unavailable_percentage : coalesce(var.promotion.max_unavailable, 1)
}

# This module intentionally does not change the node group during Terraform apply.
# The runbook is manually started after nonproduction validation and still pauses for approval.
resource "aws_ssm_document" "promote" {
  name            = "${var.name}-approved-eks-ami-promotion"
  document_type   = "Automation"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Approve and roll an existing EKS managed node group to a validated AWS-managed AMI release"
    assumeRole    = var.promotion.automation_role_arn
    parameters = {
      ApprovalReference = { type = "String", description = "Change or validation record for this exact release", allowedPattern = ".*\\S.*" }
    }
    mainSteps = [
      {
        name           = "approvePromotion"
        action         = "aws:approve"
        timeoutSeconds = var.promotion.approval_timeout
        onFailure      = "Abort"
        inputs = {
          NotificationArn      = var.promotion.notification_arn
          Message              = "Approve ${var.promotion.cluster_name}/${var.promotion.node_group_name} AMI release ${var.candidate.approved_release_version} after reviewing {{ ApprovalReference }}"
          MinRequiredApprovals = 1
          Approvers            = var.promotion.approvers
        }
      },
      {
        name           = "verifyApprovedCandidate"
        action         = "aws:executeScript"
        timeoutSeconds = 60
        onFailure      = "Abort"
        inputs = {
          Runtime = "python3.11"
          Handler = "verify_candidate"
          Script  = file("${path.module}/scripts/verify_candidate.py")
          InputPayload = {
            parameter_name  = var.candidate.parameter_name
            release_version = var.candidate.approved_release_version
            image_id        = local.candidate.image_id
            cluster_name    = var.promotion.cluster_name
            node_group_name = var.promotion.node_group_name
          }
        }
      },
      {
        name      = "verifyRolloutLimit"
        action    = "aws:assertAwsResourceProperty"
        onFailure = "Abort"
        inputs = {
          Service          = "eks"
          Api              = "DescribeNodegroup"
          clusterName      = var.promotion.cluster_name
          nodegroupName    = var.promotion.node_group_name
          PropertySelector = local.use_percentage_limit ? "$.nodegroup.updateConfig.maxUnavailablePercentage" : "$.nodegroup.updateConfig.maxUnavailable"
          DesiredValues    = [tostring(local.rollout_limit)]
        }
      },
      {
        name      = "updateNodeGroup"
        action    = "aws:executeAwsApi"
        onFailure = "Abort"
        inputs = {
          Service        = "eks"
          Api            = "UpdateNodegroupVersion"
          clusterName    = var.promotion.cluster_name
          nodegroupName  = var.promotion.node_group_name
          releaseVersion = var.candidate.approved_release_version
          force          = false
        }
        outputs = [{ Name = "UpdateId", Selector = "$.update.id", Type = "String" }]
      },
      {
        name           = "waitForHealthyUpdate"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 7200
        onFailure      = "Abort"
        inputs = {
          Service          = "eks"
          Api              = "DescribeUpdate"
          name             = var.promotion.cluster_name
          nodegroupName    = var.promotion.node_group_name
          updateId         = "{{ updateNodeGroup.UpdateId }}"
          PropertySelector = "$.update.status"
          DesiredValues    = ["Successful", "Failed", "Cancelled"]
        }
      },
      {
        name      = "verifyUpdateSucceeded"
        action    = "aws:assertAwsResourceProperty"
        onFailure = "Abort"
        inputs = {
          Service          = "eks"
          Api              = "DescribeUpdate"
          name             = var.promotion.cluster_name
          nodegroupName    = var.promotion.node_group_name
          updateId         = "{{ updateNodeGroup.UpdateId }}"
          PropertySelector = "$.update.status"
          DesiredValues    = ["Successful"]
        }
      },
      {
        name           = "verifyNodeGroupActive"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 600
        onFailure      = "Abort"
        inputs = {
          Service          = "eks"
          Api              = "DescribeNodegroup"
          clusterName      = var.promotion.cluster_name
          nodegroupName    = var.promotion.node_group_name
          PropertySelector = "$.nodegroup.status"
          DesiredValues    = ["ACTIVE"]
        }
      },
      {
        name      = "verifyInstalledRelease"
        action    = "aws:assertAwsResourceProperty"
        onFailure = "Abort"
        inputs = {
          Service          = "eks"
          Api              = "DescribeNodegroup"
          clusterName      = var.promotion.cluster_name
          nodegroupName    = var.promotion.node_group_name
          PropertySelector = "$.nodegroup.releaseVersion"
          DesiredValues    = [var.candidate.approved_release_version]
        }
      },
      {
        name           = "confirmWorkloadHealth"
        action         = "aws:approve"
        timeoutSeconds = var.promotion.approval_timeout
        onFailure      = "Abort"
        inputs = {
          NotificationArn      = var.promotion.notification_arn
          Message              = "Confirm Ready nodes, healthy pods, PDBs and application smoke tests for ${var.promotion.cluster_name}/${var.promotion.node_group_name}. Record evidence in {{ ApprovalReference }}. Reject on any failure and follow the replacement-group recovery procedure."
          MinRequiredApprovals = 1
          Approvers            = var.promotion.approvers
        }
      }
    ]
  })
  tags = var.tags
  lifecycle {
    precondition {
      condition     = local.candidate.release_version == var.candidate.approved_release_version
      error_message = "The candidate parameter no longer matches the release version validated in nonproduction."
    }
  }
}
