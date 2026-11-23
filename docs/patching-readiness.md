# Patching validation and production readiness

These modules cover EC2 operating-system patches and AWS-managed EKS AMI releases. Application and container dependency updates are outside this PR.

## Before scheduling production

1. Require the `terraform-validate` status in repository branch protection (it aggregates both modules and their tests). Review a saved Terraform plan: exact tag intersections, enumerated target IDs, baseline OS/classifications/rejections, time zone, window duration/cutoff, concurrency/error limits, document versions, IAM roles, approver ARNs and subscribed SNS channel. Production configuration creates an enabled schedule. Keep `production = null` until validation is accepted.
2. Back up data and application configuration consistently. Record EC2 AMI/EBS snapshot IDs and restore a replacement instance; verify boot, SSM access and application smoke tests. `NoReboot` image creation alone does not guarantee application-consistent backups.
3. Record the EKS current and approved release/AMI IDs. Verify spare subnet IPs, quotas/capacity, PDBs and rollout limits. Deploy representative workloads to a disposable node group, update it and verify Ready nodes, pod restarts, rollout status and application availability.
4. Rehearse recovery. EKS `UpdateNodegroupVersion` **cannot downgrade** to an earlier AMI. Create a replacement group using the previously validated release, validate it, move workloads under PDB control and then remove the failed group. An approved forward fix is another option. Never force drain past a PDB just to make the test pass.
5. Test SNS subscription delivery, topic/KMS permissions and routing into the team's monitoring channel. Both modules emit execution status events to their approval topic. Merge `notification_policy_statement` into that topic's existing policy; do not overwrite other statements. For an encrypted topic, its KMS key must permit EventBridge `kms:GenerateDataKey` and `kms:Decrypt`. Monitor EventBridge `FailedInvocations`; an API-successful target registration does not prove message delivery.

## Live acceptance matrix

Use a dedicated nonproduction instance/group, a named operator and a bounded maintenance window. Retain identifiers and outputs in private change evidence; never commit account-specific evidence here.

| Scenario | Expected result and evidence |
| --- | --- |
| EC2 Scan | Only the intended Environment AND PatchGroup intersection is targeted; record command IDs, instance IDs, baseline and compliance counts. Verify negative tag matches are excluded. |
| EC2 Install + approval | Approval precedes mutation; verify reboot behavior, fresh post-install scan, EC2 instance/system status and application smoke tests before final health approval. |
| Rejection | Reject the first approval. Execution fails and installation/update steps remain unexecuted. |
| Approval timeout | Leave approval unanswered. Execution times out and mutation remains unexecuted. |
| Window/cutoff/target drift | Approve after cutoff, with another window's execution ID, or after changing a target tag; installation must not start. |
| Failed installation | Inject a failing command on a disposable fixture. Automation aborts; compliance/application success must not be reported. Retain the command output and notification. |
| EKS candidate drift | Change the validation fixture's candidate AMI/release after planning; approve and verify the runtime guard aborts before the update. |
| EKS update success | Exact release and AMI pass the runtime guard, rollout limits match, `force=false`, update succeeds, node group is ACTIVE and the installed release matches. Record node/pod/application evidence before final approval. |
| Failed EKS update | Inject an update API failure or a PDB-blocked disposable rollout. Record failure details, prove later success gates do not run, and exercise replacement-group recovery. |
| Post-change health failure | Reject the final approval. Execution fails even if infrastructure installation/update succeeded; start incident recovery. Approval timeout also fails. |
| Notifications | Successful, failed and waiting executions are visible; verify failure delivery in the actual subscribed monitoring destination. |
| Recovery | Restore the EC2 backup and create the EKS replacement group, then verify application health and clean up the disposable resources. |

## Execution and reporting

Pin the numeric Automation document version when starting a manually executed runbook. EC2 scheduled tasks pin their deployed document version. Approvers must inspect that version and its change record. Limit document-update and `ssm:StartAutomationExecution` permissions to the authorized operators; approval does not protect an execution whose runbook was modified by an untrusted writer.

```sh
aws ssm start-automation-execution --document-name "$PROMOTION_DOCUMENT" \
  --document-version "$DOCUMENT_VERSION" \
  --parameters "ApprovalReference=$CHANGE_REFERENCE" \
  --profile "$AWS_PROFILE" --region "$AWS_REGION"

# Requires boto3. Read-only; full command output may contain operational details.
python3 scripts/patching_report.py --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --instance-id "$INSTANCE_ID" --document-name "$PATCH_DOCUMENT" \
  --document-name "$PROMOTION_DOCUMENT" > private-patching-evidence.json
```

The report includes affected instance IDs, raw patch compliance states, command statuses/output, Automation parameters and step results. Missing compliance data is reported as unavailable. Its counts are execution records, including parent Automations and child commands, rather than unique changes. Treat `Waiting`, `Pending` and `InProgress` as unfinished work. Reconcile EventBridge notifications against this API report because event delivery is best effort.

Nonproduction scheduled Scan/Install results remain in Run Command/Maintenance Windows. Set `nonproduction_notification_arn` to route their window status to an existing topic, and grant its published rule ARN `events.amazonaws.com` `sns:Publish` in the topic policy.

## Role review

The caller supplies roles; these modules do not create broad IAM policies.

- Maintenance Window role: trust `ssm.amazonaws.com`; scope `ssm:StartAutomationExecution` to the versioned/unversioned Automation definition **and** the account/region `automation-execution/*` resource (SSM checks execution creation separately), `ssm:GetDocument` to the document and `iam:PassRole` to the Automation role. Allow execution readback, target/resource-group discovery and the nonproduction Run Command actions needed by the selected targets.
- EC2 Automation role: `ssm:GetMaintenanceWindow`, `ssm:GetMaintenanceWindowExecution`, `ssm:DescribeMaintenanceWindowExecutions`, `ssm:DescribeInstancePatchStates`, `ssm:DescribeInstanceInformation` (the Run Command action checks SSM availability), Run Command send/read permissions, `ec2:DescribeInstances`, `ec2:DescribeInstanceStatus`, and `sns:Publish` to the approval topic. Scope `ssm:SendCommand` to `AWS-RunPatchBaseline` and the intended instance ARNs/tag conditions. Describe/list APIs often require `Resource = "*"`; do not use that as justification to broaden write actions.
- EKS Automation role: `ssm:GetParameter` on the candidate parameter, `ec2:DescribeImages`, `ec2:DescribeLaunchTemplateVersions` for groups using templates, `eks:DescribeNodegroup`, `eks:UpdateNodegroupVersion`, `eks:DescribeUpdate`, and approval-topic `sns:Publish`. `DescribeUpdate` requires the cluster ARN; update/describe-nodegroup permissions must match the node-group ARN. Scope update to the intended group.
- Approvers: named IAM principals with `ssm:SendAutomationSignal` and execution-read permissions; test both allowed and unauthorized identities. SSM-managed instances need an SSM instance profile and endpoint connectivity.

## Failure response

Disable future Maintenance Window schedules before investigating. `CANCEL_TASK` prevents queued tasks after cutoff; it does not undo commands already started. Rejecting a health approval, cancelling an Automation or timing out also does not revert completed changes. Capture execution/command/update IDs and errors, notify the owner, and follow the verified EC2 restore or EKS replacement procedure. Resume production only after reviewing the final plan, live acceptance evidence and recovery results.

References: [SSM approvals](https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-action-approve.html), [SSM event schemas](https://docs.aws.amazon.com/systems-manager/latest/userguide/monitoring-systems-manager-event-examples.html), [EKS update and recovery constraints](https://docs.aws.amazon.com/eks/latest/APIReference/API_UpdateNodegroupVersion.html).

The [nonproduction validation results](patching-validation-results.md) record the bounded fixture tests and the deployment-specific gates that remain.
