# Feature Specification: EC2 patching and EKS AMI updates

**Feature Branch**: `001-dmvp-10649-patch-automation`
**Created**: 2026-11-09
**Status**: Draft
**Input**: DMVP-10649 and operator clarification: implement ordinary EC2 patching and EKS worker AMI replacement as separate modules in terraform-aws-ec2-service.

## User Scenarios & Testing

### User Story 1 - Patch nonproduction EC2 safely (Priority: P1)

An operator selects managed EC2 instances by environment and patch group, scans them, and installs approved OS patches in a bounded nonproduction window.

**Why this priority**: It proves targeting and patch behavior before production use.

**Independent Test**: Configure a nonproduction patch group, run its window, and verify only intended instances received patch commands and compliance results.

**Acceptance Scenarios**:

1. **Given** a nonproduction instance with matching tags, **when** the window runs, **then** scanning and installation target that instance.
2. **Given** a production instance, **when** the nonproduction window runs, **then** it receives no patch command.

### User Story 2 - Approve production EC2 installation (Priority: P1)

A named approver reviews a production patch execution and explicitly approves it before installation can start.

**Why this priority**: Production patching can restart workloads.

**Independent Test**: Start a production window and verify installation remains paused until approval, with denial or timeout stopping execution.

**Acceptance Scenarios**:

1. **Given** no approval, **when** the production schedule fires, **then** installation does not start.
2. **Given** approval from a designated approver, **when** the execution resumes, **then** bounded installation can run and approval evidence remains available.

### User Story 3 - Promote EKS worker AMIs safely (Priority: P2)

An operator selects a newly AWS-published worker AMI with the required fixes, validates it in nonproduction, and promotes it to production through a separate node replacement workflow with explicit approval and rollback.

**Why this priority**: EKS worker nodes should be replaced with updated images rather than patched in place.

**Independent Test**: Verify an AMI candidate can be identified and validated without changing production, then demonstrate a controlled node-group replacement and rollback in a test cluster.

**Acceptance Scenarios**:

1. **Given** a candidate AMI, **when** validation fails, **then** production promotion remains blocked.
2. **Given** approved promotion, **when** nodes are replaced, **then** application and node health checks run and the prior AMI remains available for rollback.

### Edge Cases

- Missing SSM Agent, IAM permissions, or network access makes an instance ineligible and is reported.
- A missing approver or invalid production schedule prevents enabling production installation.
- Approval denial, expiry, patch command failure, and health-check failure stop subsequent rollout phases.
- A patch-group/environment tag collision must not allow a nonproduction task to select production nodes.

## Requirements

### Functional Requirements

- **FR-001**: Infrastructure configuration MUST define patch baselines and environment-specific patch groups for explicitly supported OS families.
- **FR-002**: Nonproduction scanning and installation MUST be separately schedulable and restricted to matching nonproduction tags.
- **FR-003**: Production installation MUST use a dedicated schedule and require recorded approval from named approvers for every execution.
- **FR-004**: Production installation MUST remain disabled when an approver or schedule is absent.
- **FR-005**: Every installation MUST have bounded concurrency and error thresholds.
- **FR-006**: Operators MUST be able to inspect compliance, failed executions, targets, and approval records.
- **FR-007**: A separate EKS worker AMI workflow MUST discover an AWS-published fixed candidate, expose its identifier, and support nonproduction validation before production promotion. It MUST NOT build or patch a new AMI.
- **FR-008**: EKS production rollout MUST replace nodes in phases with approval, health checks, and a documented path to the previous AMI or launch-template version.
- **FR-009**: Validation and rollback procedures MUST be documented and exercised in nonproduction before production eligibility.
- **FR-010**: No module deployment alone MUST trigger an unapproved production patch installation or EKS node replacement.

### Key Entities

- **Patch policy**: OS family, approved classifications and severities, rejection rules, and approval delay.
- **Patch target**: Environment and patch-group tags.
- **Execution approval**: Named approver, decision, timestamp, and execution identifier.
- **AMI candidate**: Image identifier, source, validation status, and previous version.

## Success Criteria

- **SC-001**: In a nonproduction test, 100% of patch commands target the intended environment and 0 production instances.
- **SC-002**: In a production simulation, 0 installations begin before an explicit approval.
- **SC-003**: A failed or denied execution stops before the next rollout phase and can be traced to a target and execution record.
- **SC-004**: A nonproduction EKS rollout can return to the prior worker image using documented steps.

## Assumptions

- A checked local setup uses an Amazon Linux EC2 AMI; other OS families are enabled only when configured explicitly.
- The operator has not yet supplied a shared patch schedule or named production approvers. These remain deployment-specific required inputs rather than hard-coded defaults.
- This feature creates reusable modules and test evidence. Live nonproduction and production execution require separately identified accounts, targets, and approvals.
