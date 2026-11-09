# Implementation Plan: EC2 patching and EKS AMI updates

**Branch**: `001-dmvp-10649-patch-automation` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

## Technical Context

- Terraform AWS modules under `modules/`; the root service module wraps EC2 and ALB.
- Add two independent submodules; preserve the root interface and existing behavior.
- EC2: SSM baseline, patch-group registration, nonproduction Maintenance Window tasks, and production Automation with `aws:approve` before `aws:runCommand`.
- EKS: discover an AWS-published fixed AMI and use controlled managed-node-group replacement. Do not build or patch a custom AMI.
- No live AWS mutation in local tests. Nonproduction integration and rollback rehearsal need a named account and cluster.

## Constitution and module standards

- `.specify/memory/constitution.md` is the bootstrap template; no repository-specific constitution exists.
- Follow DasMeta grouped object inputs, inline field descriptions, `versions.tf`, examples, native tests, and README conventions.
- Existing EC2 module wraps `terraform-aws-modules/ec2-instance/aws`. No provider-maintained Terraform module covers this patch orchestration, so use AWS provider resources in separate submodules.
- EKS best practice is node replacement with rolling managed-node-group updates that respect Pod Disruption Budgets.

## Design gates

1. Production SSM schedule invokes an approval-first Automation document only. It rechecks window time and target tags before installation. No scheduled Run Command Install task.
2. Targets match environment and patch-group tags; production and nonproduction values cannot overlap.
3. EKS candidate discovery never triggers promotion. A distinct approved version/input and reviewed plan are required.
4. Do not create a custom AMI or silently convert a node group to custom AMI management.
5. Consumer supplies OS, schedule, and approvers; no customer-specific defaults.

## Structure and verification

- `modules/ssm-patch-management/{main,variables,outputs,versions}.tf` and native tests.
- `modules/eks-ami-promotion/{main,variables,outputs,versions}.tf` and native tests.
- Independent examples under `examples/`.
- Run `terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`, and `terraform test` for the submodules.
- Inspect a nonproduction plan, run scan/install, verify compliance and health, and rehearse rollback before production adoption.

## Risks and rollout

- This is additive; existing root consumers are unaffected.
- The new modules can create scheduled actions. Production installation must be disabled until approval and schedule values are supplied.
- Live acceptance criteria require nonproduction evidence and later operator-approved production rollout. A PR alone does not satisfy them.
