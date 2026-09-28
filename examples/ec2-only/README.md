# ec2-only

Run from this directory:

```sh
terraform init
terraform plan
```

Supply the required variables from variables.tf using your deployment's values.
The example uses existing networking and does not provision an application.
ALBs are internal and deletion-protected by default. For public ALBs, explicitly
set internal=false and choose correctly routed public subnets. Before teardown,
set enable_deletion_protection=false and apply that setting.

Review the [root documentation](../../README.md) for network ownership and testing.
