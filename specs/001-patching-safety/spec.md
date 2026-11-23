# Feature Specification: Patching safety

**Branch**: DMVP-10649-patch-automation
**Created**: 2026-11-23
**Status**: Implementation requested
**Input**: Fix PR #15 using the supplied review.

## User Scenarios & Testing

### US1 — Safe EC2 patching (P1)
An operator approves patching only inside the intended maintenance window and target group. Rejection, timeout, closed windows, wrong tags, failed installation, or noncompliance prevent successful completion. Instance recovery and application health must be confirmed before closing the change.
Independent test: exercise allowed and rejected targets, failed checks, and scan-only mode.

### US2 — Safe EKS promotion (P1)
An operator approves an exact tested release. Candidate drift, unhealthy node groups, or changed rollout limits block mutation. Failed updates stop the workflow. Node, pod, and application health must be confirmed before success.
Independent test: simulate changed releases and failed updates; rehearse replacement-node-group recovery in nonproduction.

### US3 — Evidence and notifications (P2)
Maintainers receive failing CI when either module regresses. Operators can see successful, failed, and pending executions and affected instances, with failure notifications routed to their monitoring subscription.
Independent test: both modules' tests run in CI; inject a failed execution and verify delivery.

## Requirements

- FR1: Check both new modules in the required validation aggregate, including discovered tests and lint.
- FR2: Production stays disabled by default and requires named approval. Preserve dual-tag targeting and recheck the configured window and target after approval.
- FR3: Make reboot behavior explicit, verify patch compliance and instance status, require application-health sign-off.
- FR4: Verify the candidate release and image at execution time after approval; preserve rollout limits and graceful draining.
- FR5: Check final EKS release and status and require node/pod/application-health sign-off.
- FR6: Expose execution status events for monitoring and document compliance/affected-instance reporting.
- FR7: Provide nonproduction failure-path tests and recovery/readiness evidence; never claim mocked tests prove live AWS behavior.
- FR8: Exclude application and container dependency upgrades.

## Edge Cases

Approval rejection/timeout, stale candidate, mismatched tag, disabled/closed window, failed patch, pending reboot, impaired instance, failed EKS update, blocked PDB, unhealthy application, and notification permissions.

## Success Criteria

All automated safety checks pass locally and in CI for both modules. Every rejected safety condition stops before the next mutation or prevents success. Each live readiness scenario has an execution ID and health/recovery evidence before production enablement.

## Assumptions

Keep existing inputs compatible; use named human sign-off for application-specific health because no generic workload probe is known. Production rollout is outside this PR fix. Live nonproduction evidence is environment-specific and is retained locally.
