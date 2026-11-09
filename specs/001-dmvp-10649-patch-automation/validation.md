# Validation record — 2026-11-09

## Completed local checks

- `modules/ssm-patch-management`: `terraform init -backend=false -input=false -no-color`, `terraform validate -no-color`, and `terraform test -no-color` passed (2 tests, 0 failed), including production-disabled and dual-tag targeting checks.
- `modules/eks-ami-promotion`: same commands passed (2 tests, 0 failed), including rejection of a candidate release mismatch.
- `examples/ssm-patch-management` and `examples/eks-ami-promotion`: `terraform init -backend=false -input=false -no-color` and `terraform validate -no-color` passed.
- `terraform fmt -recursive` applied to the repository.
- `TFENV_TERRAFORM_VERSION=1.9.3 terraform test -no-color` passed for each new module (2 tests each, 0 failed).

## Full repository gate

- The first `bash scripts/validate.sh` attempt used Terraform 1.15.7. New-module tests passed, but an existing EC2 plan assertion script could not find its expected test-state record (`KeyError: 'secure_defaults'`).
- A second run used Terraform 1.9.3, matching the repository's 1.9 CI family. Root tests passed (32/32). The existing ALB suite passed 39/40 before its AWS provider process stopped during `empty_target_id` with a plugin handshake error; the script stopped there. Both new modules were then tested directly with 1.9.3 and passed (2/2 each).
- An isolated retry of the existing ALB suite under Terraform 1.9.3 also hit an AWS provider handshake failure during teardown (31 passed, 1 failed, 8 skipped). This is outside the new modules; its cause is not established.
- No full repository gate pass is claimed. The provider download also initially exhausted local disk space; a shared plugin cache was used for subsequent checks.
- CI workflow coverage for the two new modules is pending. The authenticated GitHub OAuth token has `repo` but lacks `workflow` scope, and GitHub rejected the attempted push containing `.github/workflows/terraform-test.yaml`. The local `scripts/validate.sh` includes both new modules; the GitHub workflow update needs a correctly scoped Adeline connection.

## Unverified acceptance criteria

- No AWS account, maintenance window, approver, or target group was supplied. No live nonproduction scan, install, compliance readout, application smoke test, or rollback rehearsal occurred.
- No production approval execution occurred. Automation runbook ordering is covered by a mocked plan test, not an AWS integration test.
- The EKS module uses an AWS-built EKS-optimized AMI release. The operator explicitly ruled out building or patching a new image; this is now the intended design, reflected in the Jira epic.
- EKS managed-node-group update and rollback behavior were not exercised against a cluster.
