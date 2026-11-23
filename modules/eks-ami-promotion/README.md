# EKS AMI promotion

Creates a manually started, approval-controlled SSM Automation for an existing managed node group using an AWS-managed EKS AMI. Terraform apply never starts the update.

After approval, the runbook re-reads the candidate parameter and verifies both the pinned release and AMI ID, checks that the Amazon-owned image is available and compatible with an ACTIVE, healthy node group, rejects custom AMIs, and checks the current rollout limit. It updates with `force = false`, waits for a terminal update status, fails immediately on Failed/Cancelled, then verifies ACTIVE status and the installed release. A final named approval requires node readiness, pod health, PDB and application smoke-test evidence. Those workload checks are performed by the approver; the module does not have Kubernetes credentials or infer application health from EKS status.

The caller supplies least-privilege IAM roles and approvers. Status events route to the existing approval SNS topic, including failed/rejected/timed-out executions. Merge `notification_policy_statement` into the topic policy and validate subscription/KMS delivery.

Use the [production readiness and recovery procedure](../../docs/patching-readiness.md). EKS cannot downgrade an existing node group to an older AMI with UpdateNodegroupVersion; recovery requires a tested replacement group or approved forward fix. Use AWS-managed releases without a custom AMI or custom ImageId in a launch template.

Initialize with `terraform init -backend=false`; then run `terraform validate` and `terraform test` in this directory. See [example](../../examples/eks-ami-promotion). Mock tests verify configuration and guard behavior; live execution evidence is required before production.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.37 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.37 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.execution_status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.execution_status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_ssm_document.promote](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [aws_eks_node_group.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_node_group) | data source |
| [aws_ssm_parameter.candidate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_candidate"></a> [candidate](#input\_candidate) | SSM parameter identifying a candidate EKS-optimized AMI release. | <pre>object({<br/>    parameter_name           = string # Public or private SSM parameter containing JSON with image_id and release_version.<br/>    approved_release_version = string # Release version validated in nonproduction and pinned for this runbook.<br/>  })</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for the AMI promotion runbook. | `string` | n/a | yes |
| <a name="input_promotion"></a> [promotion](#input\_promotion) | Existing managed node group and approval settings; this module never starts a promotion automatically. | <pre>object({<br/>    cluster_name               = string                 # Existing EKS cluster name.<br/>    node_group_name            = string                 # Existing managed node group name.<br/>    automation_role_arn        = string                 # Role allowed to describe and update this node group.<br/>    notification_arn           = string                 # SNS topic for manual approval requests.<br/>    approvers                  = list(string)           # Named IAM approver ARNs.<br/>    approval_timeout           = optional(number, 3600) # Seconds before an unanswered request aborts.<br/>    max_unavailable            = optional(number)       # Existing absolute node rollout limit, if configured.<br/>    max_unavailable_percentage = optional(number)       # Existing percentage node rollout limit, if configured.<br/>  })</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for the SSM runbook. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_candidate_ami_id"></a> [candidate\_ami\_id](#output\_candidate\_ami\_id) | Candidate image ID from the SSM parameter; validation is still required. |
| <a name="output_candidate_release_version"></a> [candidate\_release\_version](#output\_candidate\_release\_version) | Candidate EKS AMI release version; pin as approved\_release\_version after validation. |
| <a name="output_current_release_version"></a> [current\_release\_version](#output\_current\_release\_version) | Current node-group AMI release version at plan time; record it before promotion for replacement-group recovery. |
| <a name="output_notification_policy_statement"></a> [notification\_policy\_statement](#output\_notification\_policy\_statement) | Merge into the existing SNS topic policy; do not replace its other statements. The topic and any KMS key must permit EventBridge publication. |
| <a name="output_promotion_document_arn"></a> [promotion\_document\_arn](#output\_promotion\_document\_arn) | Manual approval-first runbook ARN. Terraform apply does not start the runbook. |
<!-- END_TF_DOCS -->
