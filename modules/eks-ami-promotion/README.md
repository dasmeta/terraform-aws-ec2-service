# EKS AMI promotion

Reads a candidate EKS-optimized AMI record from SSM Parameter Store and creates a manually started Automation runbook. A pinned release version must match the candidate record. The runbook requests approval, checks the existing managed node group's `maxUnavailable` setting, then calls `UpdateNodegroupVersion` with `force = false` and waits for a successful update. Terraform apply does not start the runbook or modify the node group.

Use this for **AWS-managed EKS AMI releases on an existing managed node group without a custom AMI**. AWS publishes images containing the fixes; this workflow selects and validates those images. Do not build a new image, patch live EKS workers in place, or edit an EKS-generated launch template. See [AWS EKS node update guidance](https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html).

Before running the document, test the exact release in nonproduction, record node and application health, verify Pod Disruption Budgets and the configured `maxUnavailable`, and retain the previous release version. Start Automation with `ApprovalReference` pointing to the validation/change record. A named approver must approve the execution. Monitor `DescribeUpdate`, node readiness, workload smoke tests, and logs. On failed validation, stop further rollout and restore the prior release using an approved node-group update or a replacement node group as appropriate to AWS rollback constraints.

This module does not configure the existing node group's update policy or prove live rollback. Those checks remain part of the rollout work for DMVP-10649.

Initialize with `terraform init -backend=false`; then run `terraform validate` and `terraform test` in this directory. See `examples/eks-ami-promotion`.
