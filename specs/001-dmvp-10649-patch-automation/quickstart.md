# Quickstart and validation

1. Configure a nonproduction patch group, Amazon Linux baseline, and window.
2. Check SSM prerequisites and inspect the plan to confirm production tags are excluded.
3. Run scan and nonproduction install; inspect compliance, instance health, and application smoke tests.
4. Configure a production schedule, approvers, and notification topic. Verify a scheduled execution waits for approval and denial or expiry aborts it.
5. Select an AWS-published fixed EKS AMI candidate. Validate in a nonproduction node group, record the prior version, and rehearse rollback.
6. Promote only after reviewing validation and the production plan.

This guide does not authorize live execution.
