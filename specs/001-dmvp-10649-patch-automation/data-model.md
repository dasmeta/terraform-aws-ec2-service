# Data model

- **Patch baseline**: OS, classifications, severities, approval delay, rejected patches; associated with patch group.
- **Patch target**: required environment and patch-group tags.
- **Maintenance window**: schedule, time zone, duration, cutoff, concurrency, error threshold.
- **Approval**: approver ARNs, notification topic, Automation execution, decision, timestamp.
- **AMI candidate**: AWS-published image ID, release version, validation status.
- **EKS promotion**: cluster, node group, candidate and prior AMI/launch-template version, approval reference, update status.
