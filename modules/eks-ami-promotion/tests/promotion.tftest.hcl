mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "{\"image_id\":\"ami-0123456789abcdef0\",\"release_version\":\"1.31.0-20261109\"}"
    }
  }
  mock_data "aws_eks_node_group" {
    defaults = {
      release_version = "1.31.0-20261001"
    }
  }
}

variables {
  name = "example"
  candidate = {
    parameter_name           = "/aws/service/eks/optimized-ami/1.31/amazon-linux-2023/x86_64/standard/recommended"
    approved_release_version = "1.31.0-20261109"
  }
  promotion = {
    cluster_name        = "example"
    node_group_name     = "workers"
    automation_role_arn = "arn:aws:iam::123456789012:role/eks-promotion"
    notification_arn    = "arn:aws:sns:us-east-1:123456789012:AutomationApproval"
    approvers           = ["arn:aws:iam::123456789012:role/EksApprover"]
  }
}

run "candidate_is_not_auto_promoted" {
  command = plan
  assert {
    condition     = output.candidate_ami_id == "ami-0123456789abcdef0"
    error_message = "Candidate AMI ID must be exposed."
  }
  assert {
    condition     = output.current_release_version == "1.31.0-20261001"
    error_message = "Current release must be exposed for rollback planning."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.promote.content).mainSteps[0].action == "aws:approve"
    error_message = "Promotion must begin with manual approval."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.promote.content).mainSteps[3].inputs.Api == "UpdateNodegroupVersion"
    error_message = "Promotion must update the managed node group after approval."
  }
}

run "reject_unvalidated_release" {
  command = plan
  variables {
    candidate = {
      parameter_name           = "/aws/service/eks/optimized-ami/1.31/amazon-linux-2023/x86_64/standard/recommended"
      approved_release_version = "1.31.0-not-validated"
    }
  }
  expect_failures = [aws_ssm_document.promote]
}

run "accept_percentage_rollout_limit" {
  command = plan
  variables {
    promotion = {
      cluster_name               = "example"
      node_group_name            = "workers"
      automation_role_arn        = "arn:aws:iam::123456789012:role/eks-promotion"
      notification_arn           = "arn:aws:sns:us-east-1:123456789012:AutomationApproval"
      approvers                  = ["arn:aws:iam::123456789012:role/EksApprover"]
      max_unavailable_percentage = 33
    }
  }
  assert {
    condition     = jsondecode(aws_ssm_document.promote.content).mainSteps[2].inputs.PropertySelector == "$.nodegroup.updateConfig.maxUnavailablePercentage"
    error_message = "The guard must check the existing percentage rollout limit."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.promote.content).mainSteps[2].inputs.DesiredValues == ["33"]
    error_message = "The guard must check the exact percentage configured on the node group."
  }
}

run "reject_zero_percentage_rollout_limit" {
  command = plan
  variables {
    promotion = {
      cluster_name               = "example"
      node_group_name            = "workers"
      automation_role_arn        = "arn:aws:iam::123456789012:role/eks-promotion"
      notification_arn           = "arn:aws:sns:us-east-1:123456789012:AutomationApproval"
      approvers                  = ["arn:aws:iam::123456789012:role/EksApprover"]
      max_unavailable_percentage = 0
    }
  }
  expect_failures = [var.promotion]
}

run "runtime_guards_and_health_signoff" {
  command = plan
  assert {
    condition = tolist([for step in jsondecode(aws_ssm_document.promote.content).mainSteps : step.name]) == tolist([
      "approvePromotion", "verifyApprovedCandidate", "verifyRolloutLimit", "updateNodeGroup",
      "waitForHealthyUpdate", "verifyUpdateSucceeded", "verifyNodeGroupActive", "verifyInstalledRelease", "confirmWorkloadHealth"
    ])
    error_message = "Runtime candidate verification and health gates must surround the update."
  }
  assert {
    condition     = alltrue([for step in jsondecode(aws_ssm_document.promote.content).mainSteps : step.onFailure == "Abort"])
    error_message = "Every failed, rejected or timed-out step must abort."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.promote.content).mainSteps[3].inputs.force == false
    error_message = "Updates must respect Pod Disruption Budgets."
  }
  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.execution_status.event_pattern).detail.Definition == [aws_ssm_document.promote.name]
    error_message = "Execution notifications must be scoped to this document."
  }
}

run "reject_excessive_approval_timeout" {
  command = plan
  variables {
    promotion = {
      cluster_name        = "example"
      node_group_name     = "workers"
      automation_role_arn = "arn:aws:iam::123456789012:role/eks-promotion"
      notification_arn    = "arn:aws:sns:us-east-1:123456789012:AutomationApproval"
      approvers           = ["arn:aws:iam::123456789012:role/EksApprover"]
      approval_timeout    = 2592001
    }
  }
  expect_failures = [var.promotion]
}
