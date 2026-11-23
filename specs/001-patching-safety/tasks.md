# Tasks: Patching safety

## Setup
- [X] T001 Bootstrap and record review scope in specs/001-patching-safety/spec.md and plan.md.

## US1: Guard changes (P1)
- [X] T002 [US1] Add regression assertions to modules/*/tests/*.tftest.hcl and guard behavior tests under tests/patching/.
- [X] T003 [US1] Implement runtime AMI identity and health checks in modules/eks-ami-promotion/.
- [X] T004 [US1] Implement reboot, compliance, instance and application health gates in modules/ssm-patch-management/.

## US2: Observe and validate (P1)
- [X] T005 [US2] Add scoped EventBridge/SNS reporting in both modules and update examples.
- [X] T006 [US2] Include new modules and behavior tests in .github/workflows/terraform-test.yaml and scripts/validate.sh.

## US3: Production readiness (P2)
- [X] T007 [US3] Document IAM, live scenario matrix, monitoring, reboot and recovery in docs/patching-readiness.md and module READMEs.
- [X] T008 [US3] Run local checks and bounded AWS validation; record actual results and outstanding readiness gates.

## Delivery
- [X] T009 Review diff and commit/push PR fixes after checks.

Dependencies: T001 -> T002 -> T003/T004 -> T005 -> T006 -> T007 -> T008 -> T009. Work is executed sequentially in the current PR checkout.
