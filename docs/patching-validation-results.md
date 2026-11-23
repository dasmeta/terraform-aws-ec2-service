# Nonproduction validation results

Validated on 2026-11-23 using dedicated disposable EC2 instances, an isolated managed node group and a separate replacement group. No production rollout was performed. Account, resource and execution identifiers remain in private operator evidence.

| Scenario | Observed result |
|---|---|
| AWS document acceptance | AWS accepted both Automation documents. Corrected the EC2 target type to the resource-level field. |
| EC2 Scan and Install | Successful on a disposable SSM-managed Linux instance. |
| Scheduled EC2 Automation | Approved installation completed inside the configured window, with matching target tags. |
| EC2 instance and application health | Both EC2 status checks, the fresh compliance scan and HTTP smoke test passed; the named final approval completed. |
| Rejection and approval timeout | Both EC2 and EKS stopped at the approval step; installation/update steps remained pending. |
| Wrong EC2 target tags | Blocked at target verification, before installation. |
| Installer failure | An isolated cloned runbook injected a real Run Command exit code 42 at the install step. Execution failed and no health/compliance success was recorded. |
| Compliance publication delay | Observed AWS returning the preceding Install record after Scan completed. The corrected runbook waited for a scan newer than its recorded start and succeeded with zero missing, failed or reboot-pending patches. |
| Runtime AMI identity mismatch | An isolated cloned runbook injected an expected-AMI mismatch. The runtime guard failed before the update. Local tests also cover parameter drift with the same release but a different image ID. |
| EKS promotion | Approved runbook completed release verification and health sign-off. Updated nodes were Ready and the representative deployment and HTTP checks passed. |
| EKS update failure | An injected invalid release caused the AWS update API step to fail. A separate insufficient polling-permission scenario also aborted instead of reporting success. |
| EKS disruption and recovery | A representative replicated deployment with a PDB remained available. A replacement group created with the previous AMI became Ready; the deployment moved to it and passed an HTTP check. No unsupported in-place AMI downgrade was attempted. |
| EC2 backup recovery | Restored a separate instance from an AMI containing the static test application. Boot, SSM connectivity, service startup and HTTP checks passed. |
| Notification delivery | Received approval messages and execution status events through SNS into a private SQS test subscription, including success, waiting, timeout and failure. |

IAM validation identified two important permissions in addition to ordinary node-group/command permissions: `eks:DescribeUpdate` needs the cluster ARN, and `ssm:StartAutomationExecution` needs access to execution creation as well as the document definition. `aws:runCommand` also uses `ssm:DescribeInstanceInformation` to verify agent availability. The readiness procedure records these requirements. An initial stale SNS rule policy caused delivery failures; refreshing the scoped rule ARNs restored delivery. Topic-policy integration must be verified in each deployment.

Local verification used Terraform 1.9.8 to match CI. The repository validation script passed 101 native Terraform tests across root, EC2, ALB and both patching modules. The final patching suites passed 5 and 6 tests; 16 Python guard/report behavior tests passed. Terraform format/validate, TFLint for both modules and repository pre-commit checks passed.

This validates the reusable workflow with a representative fixture. Production still requires the actual target inventory, least-privilege role review, named approvers, monitoring subscriptions/KMS policy, application-specific smoke tests and application-consistent backup/recovery evidence, plus final saved-plan and schedule review. Repository owners must require the aggregate `terraform-validate` status in branch protection; adding the CI jobs alone does not configure repository rules.

See [the rollout and recovery procedure](patching-readiness.md). Production remains disabled unless explicitly configured by a consumer.
