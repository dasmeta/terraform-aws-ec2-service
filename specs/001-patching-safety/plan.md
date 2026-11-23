# Implementation Plan: Patching safety

Branch: DMVP-10649-patch-automation. Scope: PR #15 in terraform-aws-ec2-service.

## Summary and technical context
Preserve the two focused modules, grouped inputs, Terraform ~>1.9 and AWS ~>6.37. No application/container dependency updates. Add runtime release identity checks, post-change compliance/infrastructure checks, explicit human application health attestation, monitoring, and executable verification. Production remains opt-in.

## Baseline and constitution check
Existing module code directly owns SSM resources; improve mode preserves that baseline; no new upstream module is needed. Repository has docs, independent examples/tests, hooks and release automation. Gap: root-only CI omits these modules; tests are mocked; no live recovery evidence. Shared standards come from the constitution repository. Keep versions.tf and numbered example layout. Do not broaden root module scope or introduce a generic AWS pass-through. New optional reboot/notification settings are bounded to the requested review controls; no required Terraform inputs change. Application health remains an explicit named-approver sign-off after automatic infrastructure checks because reusable modules cannot infer workload endpoints.

## Speckit evidence and bootstrap
Spec Kit was absent; bootstrapped locally before module edits, then authored spec.md, plan.md, tasks.md for this review scope. Existing PR branch must remain unchanged; bootstrap scripts assume numeric branch names, so their branch-name guard rejects this ticket branch. Use the explicit feature directory and retain reviewable artifacts without renaming the PR branch. No additional approval round is needed: user requested implementing this PR review.

## Proposed files and behavior
- modules/eks-ami-promotion: Python runtime release guard embedded via file(); compare pinned release and image identity after approval, reject unhealthy/custom-AMI node groups, verify successful update, ACTIVE group, pinned release and explicit node/pod/application sign-off.
- modules/ssm-patch-management: explicit reboot policy, window identity validation, post-install Scan, fresh compliance and EC2 status checks, human application-health sign-off.
- Both: scoped EventBridge execution notifications to SNS; policy statements supplied for existing topic owners without overwriting shared policies.
- .github/workflows/terraform-test.yaml: module matrix, format, validate, native tests and Python behavior tests aggregated in existing terraform-validate check. Include module lint legs.
- scripts/validate.sh, READMEs, examples, regression tests, live validation/recovery runbook. Remove client-specific fixture content in the touched tests.

## Verification and rollout
Run native mock plans and Python guard behavior tests, Terraform fmt/validate, TFLint, then nonproduction AWS document creation and bounded executions in the authorized dev account. Use separate disposable resources for install/update/recovery testing; do not patch unrelated running workloads. Record live evidence outside the public repo. Never claim mocks prove AWS acceptance. Review before pushing over authenticated Adeline SSH. No merge or production deployment.

## Modern capabilities
Improve existing controls; no provider minimum change. EventBridge-to-SNS is supported under current provider minimum. AWS documentation confirms approval timeout maximum 2592000 seconds, Run Command reboot semantics, and EKS UpdateNodegroupVersion cannot downgrade AMIs. Recovery uses a replacement group or approved forward fix, never an unsupported API downgrade.

## Risks and recovery
Pending reboot/compliance lag/health failure must stop success. SNS topic owner must grant events.amazonaws.com Publish scoped to rule ARN; subscription and delivery must be tested. Approval cannot undo an applied patch/update. Disable future schedules on incident; restore EC2 backups or replace EKS node group using tested capacity/PDB procedure. Production readiness remains blocked until live matrix and recovery evidence pass.

## CloudBrowser
Documentation lookup for this repository returned no records. Reusable catalog identity is unresolved; do not create speculative records or publish live client evidence.
