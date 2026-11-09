# Research and decisions

- **Decision**: EC2 patching and EKS worker updates are separate. **Reason**: AWS recommends replacing EKS workers rather than patching in place. **Alternative**: Patch Manager on EKS workers rejected. Source: https://docs.aws.amazon.com/eks/latest/best-practices/protecting-the-infrastructure.html
- **Decision**: Production EC2 installation uses Automation `aws:approve` before any patch command. **Alternative**: scheduled Run Command Install rejected. Source: https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-action-approve.html
- **Decision**: EKS uses managed-node-group rolling replacement and explicit promotion. **Alternative**: changing auto-generated launch templates rejected. Source: https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html
- **Decision**: OS, schedule, and approvers are consumer inputs. Checked local Terraform shows an Amazon Linux EC2 AMI but no shared patch policy or approvers.
