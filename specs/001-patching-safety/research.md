# Research

- AWS Automation approvals: https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-action-approve.html
- EventBridge SSM event schemas: https://docs.aws.amazon.com/systems-manager/latest/userguide/monitoring-systems-manager-event-examples.html
- EKS AMI downgrade is unsupported: https://docs.aws.amazon.com/eks/latest/APIReference/API_UpdateNodegroupVersion.html
- Run Command: https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-action-runcommand.html

Application endpoints and cluster RBAC cannot be inferred by this module; named approvers must attest workload checks after infrastructure validation. Topic policies stay with their existing owner; output only the exact required policy statement.
