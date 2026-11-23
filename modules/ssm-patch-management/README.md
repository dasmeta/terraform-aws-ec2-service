# EC2 SSM patch management

Creates OS patch baselines, tag-scoped nonproduction Scan/Install windows and an optional approval-controlled production installation window. Production is disabled by default (`production = null`); supplying it creates an enabled schedule. Use one module instance per OS baseline. Null `patch_policy` uses AWS defaults.

Resource Groups require the intersection of exact `Environment` and `PatchGroup` values. Enumerate the matches before applying. `target_instance_ids` tags the listed instances; it is **not an allowlist**: other instances with the same two tags are also targeted. Production and nonproduction must use distinct environment and patch-group values.

Production approves each instance, verifies that the supplied execution belongs to the configured open maintenance window before cutoff, then rechecks the instance tags before patching. It waits for EC2 instance/system health, runs a fresh compliance scan and waits up to eight minutes for its compliance record, rejects missing/failed/rejected/reboot-pending patches, then requires application-health sign-off from a named approver. Application smoke tests are performed by the approver; EC2 status alone does not prove application availability.

`reboot_option` explicitly defaults to `RebootIfNeeded`; installation may reboot the instance. `NoReboot` leaves some patches pending until an operator reboots; such an execution fails the production compliance gate. Scan does not install patches. Maintenance concurrency defaults to one, but serial execution is not a substitute for application redundancy or backups.

The caller supplies Maintenance Window and Automation roles, SSM instance profiles, network connectivity, SNS topics and named approvers. Status events route production results to the approval topic. Merge `notification_policy_statement` into its policy, and verify subscription/KMS delivery. Optional `nonproduction_notification_arn` routes window status to an existing monitoring topic; grant EventBridge Publish using `nonproduction_notification_rule_arn`.

Follow the [production readiness, IAM, reporting and recovery procedure](../../docs/patching-readiness.md). Rehearse a consistent EC2 backup restore before enabling production; cancelling/failed health approval does not undo installed patches.

Initialize with `terraform init -backend=false`; then run `terraform validate` and `terraform test` here. See [example](../../examples/ssm-patch-management). Mock tests do not establish AWS execution acceptance.

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
| [aws_cloudwatch_event_rule.nonproduction_status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.execution_status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.nonproduction_status](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_ec2_tag.nonproduction_targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_tag) | resource |
| [aws_resourcegroups_group.targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group) | resource |
| [aws_ssm_document.approved_install](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [aws_ssm_maintenance_window.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window) | resource |
| [aws_ssm_maintenance_window_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_target) | resource |
| [aws_ssm_maintenance_window_task.nonproduction](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_task) | resource |
| [aws_ssm_maintenance_window_task.production](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_maintenance_window_task) | resource |
| [aws_ssm_patch_baseline.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_patch_baseline) | resource |
| [aws_ssm_patch_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_patch_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Prefix for patch-management resources. | `string` | n/a | yes |
| <a name="input_nonproduction"></a> [nonproduction](#input\_nonproduction) | Nonproduction target and schedule. | <pre>object({<br/>    environment         = string                     # Value of the Environment tag on nonproduction instances.<br/>    patch_group         = string                     # Value of the PatchGroup tag on nonproduction instances.<br/>    scan_schedule       = string                     # Maintenance Window cron/rate expression for compliance scans.<br/>    install_schedule    = optional(string)           # Maintenance Window cron/rate expression for patch installation; omit for scan-only.<br/>    scan_only           = optional(bool, false)      # Create only a scan window and never schedule an Install task.<br/>    target_instance_ids = optional(list(string), []) # EC2 instances to tag with Environment and PatchGroup for this target group.<br/>    schedule_timezone   = string                     # IANA time zone for both schedules.<br/>    duration            = optional(number, 3)        # Window length in hours.<br/>    cutoff              = optional(number, 1)        # Hours before end when new tasks stop.<br/>    max_concurrency     = optional(string, "1")      # Concurrent nodes per task.<br/>    max_errors          = optional(string, "0")      # Failed nodes allowed per task.<br/>    service_role_arn    = string                     # Maintenance Window service role ARN.<br/>  })</pre> | n/a | yes |
| <a name="input_nonproduction_notification_arn"></a> [nonproduction\_notification\_arn](#input\_nonproduction\_notification\_arn) | Optional existing SNS monitoring topic for nonproduction Maintenance Window status events. Topic owner must grant events.amazonaws.com sns:Publish for the rule ARN. | `string` | `null` | no |
| <a name="input_patch_policy"></a> [patch\_policy](#input\_patch\_policy) | OS patch baseline policy. Null uses AWS default baselines and creates no patch-group association. | <pre>object({<br/>    operating_system   = string                     # SSM operating-system identifier, for example AMAZON_LINUX_2023.<br/>    classifications    = list(string)               # Approved patch classifications.<br/>    severities         = optional(list(string), []) # Optional approved severities; empty selects all.<br/>    approve_after_days = optional(number, 7)        # Days after release before automatic approval.<br/>    rejected_patches   = optional(list(string), []) # Explicitly rejected patch IDs.<br/>  })</pre> | `null` | no |
| <a name="input_production"></a> [production](#input\_production) | Production approval and schedule; null disables production patching. | <pre>object({<br/>    environment         = string                 # Value of the Environment tag on production instances.<br/>    patch_group         = string                 # Value of the PatchGroup tag on production instances.<br/>    install_schedule    = string                 # Dedicated production window schedule.<br/>    schedule_timezone   = string                 # IANA time zone for production schedule.<br/>    duration            = optional(number, 3)    # Window length in hours.<br/>    cutoff              = optional(number, 1)    # Hours before end when new tasks stop.<br/>    max_concurrency     = optional(string, "1")  # Concurrent approved automations.<br/>    max_errors          = optional(string, "0")  # Failed automations allowed.<br/>    service_role_arn    = string                 # Maintenance Window service role ARN.<br/>    automation_role_arn = string                 # Automation role allowed to run the patch command.<br/>    notification_arn    = string                 # SNS topic ARN for approval notifications.<br/>    approvers           = list(string)           # IAM user/role ARNs allowed to approve each execution.<br/>    approval_timeout    = optional(number, 3600) # Seconds before unapproved execution aborts.<br/>  })</pre> | `null` | no |
| <a name="input_reboot_option"></a> [reboot\_option](#input\_reboot\_option) | AWS-RunPatchBaseline reboot behavior. NoReboot can leave pending patches and fails the production compliance gate until resolved. | `string` | `"RebootIfNeeded"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for created resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_maintenance_window_ids"></a> [maintenance\_window\_ids](#output\_maintenance\_window\_ids) | Created scan, optional nonproduction install, and optional production window IDs. |
| <a name="output_nonproduction_notification_rule_arn"></a> [nonproduction\_notification\_rule\_arn](#output\_nonproduction\_notification\_rule\_arn) | Grant this rule ARN events.amazonaws.com sns:Publish in the existing nonproduction topic policy. |
| <a name="output_notification_policy_statement"></a> [notification\_policy\_statement](#output\_notification\_policy\_statement) | Merge into the existing SNS topic policy; do not replace its other statements. The topic and any KMS key must permit EventBridge publication. |
| <a name="output_patch_baseline_id"></a> [patch\_baseline\_id](#output\_patch\_baseline\_id) | Created patch baseline identifier, or null when AWS defaults are used. |
| <a name="output_production_approval_document_arn"></a> [production\_approval\_document\_arn](#output\_production\_approval\_document\_arn) | Approval-first production installation Automation document ARN, or null. |
<!-- END_TF_DOCS -->
