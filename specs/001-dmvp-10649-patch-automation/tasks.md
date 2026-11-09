# Tasks: EC2 patching and EKS AMI updates

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md)

## Phase 1: Setup

- [x] T001 Verify existing module conventions and AWS provider constraints in `modules/ec2/` and `versions.tf`.
- [x] T002 Create isolated module directories under `modules/ssm-patch-management/` and `modules/eks-ami-promotion/`.

## Phase 2: Foundation

- [x] T003 [P] Define grouped, validated interfaces in `modules/ssm-patch-management/variables.tf` and `modules/eks-ami-promotion/variables.tf`.
- [x] T004 [P] Define provider constraints and outputs in both new submodules.

## Phase 3: User Story 1, nonproduction EC2 patching

**Independent test**: A nonproduction plan targets only matching environment and patch-group tags.

- [x] T005 [US1] Implement patch baseline and patch group in `modules/ssm-patch-management/main.tf`.
- [x] T006 [US1] Implement scan and install nonproduction windows with bounded task settings in `modules/ssm-patch-management/main.tf`.
- [x] T007 [US1] Add plan assertions in `modules/ssm-patch-management/tests/patch.tftest.hcl`.

## Phase 4: User Story 2, production approval

**Independent test**: Production schedule cannot invoke installation before approval.

- [x] T008 [US2] Add approval-first Automation document and production window in `modules/ssm-patch-management/main.tf`.
- [x] T009 [US2] Add validations for approvers, tags, and schedule in `modules/ssm-patch-management/variables.tf`.
- [x] T010 [US2] Test approval ordering and install-task absence in `modules/ssm-patch-management/tests/patch.tftest.hcl`.

## Phase 5: User Story 3, EKS AMI promotion

**Independent test**: Candidate discovery alone does not change a node group; explicit approved version does.

- [x] T011 [US3] Implement candidate lookup and controlled promotion in `modules/eks-ami-promotion/main.tf`.
- [x] T012 [US3] Expose candidate and current image/version outputs in `modules/eks-ami-promotion/outputs.tf`; record the current version before promotion as the prior version.
- [x] T013 [US3] Add plan assertions in `modules/eks-ami-promotion/tests/promotion.tftest.hcl`.

## Phase 6: Documentation and validation

- [x] T014 [P] Add independent examples and README guidance for both modules.
- [x] T015 Run Terraform format, init, validate, and native tests; record results in `specs/001-dmvp-10649-patch-automation/validation.md`.
- [x] T016 Document nonproduction live checks, rollback rehearsal, and unverified acceptance criteria in module READMEs.

## Dependencies

T001 -> T002 -> T003/T004 -> T005/T006/T007 -> T008/T009/T010 -> T011/T012/T013 -> T014/T015/T016.

## Parallel opportunities

T003 and T004 can be developed independently by module. Documentation can follow each completed module.

## Delivery strategy

Build and verify the EC2 nonproduction path, add the production approval gate, then implement EKS promotion. Live rollout waits for named targets, schedules, approvers, and operator approval.
