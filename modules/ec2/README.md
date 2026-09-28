# EC2 instance wrapper

Creates one EC2 instance using `terraform-aws-modules/ec2-instance/aws` pinned to
`6.4.0`. Requires Terraform `~> 1.9` and AWS provider `~> 6.37` configured by the
caller. Supply an AMI compatible with the selected instance type, plus an existing
VPC and subnet.

```hcl
module "ec2" {
  source = "./modules/ec2"

  name = "api"
  config = {
    ami       = "ami-0123456789abcdef0"
    vpc_id    = "vpc-0123456789abcdef0"
    subnet_id = "subnet-0123456789abcdef0"
    security_group = {
      ingress_rules = {
        application = {
          port                         = 8080
          referenced_security_group_id = "sg-0123456789abcdef0"
        }
      }
    }
  }
  tags = { Environment = "production" }
}
```

The public inputs are `name` (nonempty string), `config` (required object), and
`tags` (map of strings, default `{}`).

| `config` field | Default / requirement |
| --- | --- |
| `ami`, `vpc_id`, `subnet_id` | Required nonempty strings |
| `instance_type` | `t3.micro` |
| `key_name` | `null`; existing EC2 key pair name |
| `iam_instance_profile` | `null`; existing IAM instance profile name |
| `user_data` | `null`; plain UTF-8 startup script |
| `associate_public_ip_address` | `false` |
| `monitoring` | `true` |
| `root_volume.size` | `20`; positive integer GiB |
| `root_volume.type` | `gp3`; accepts `gp3` or `gp2` |
| `root_volume.kms_key_id` | `null`; optional KMS key ID or ARN |
| `security_group.create` | `true` |
| `security_group.ids` | `[]`; additional existing security groups |
| `security_group.ingress_rules` | `{}`; named TCP rules |

Each ingress rule requires integer `port` from 1 to 65535 and exactly one source:
`cidr_ipv4` (valid IPv4 CIDR) or `referenced_security_group_id`. An optional
`description` documents the rule. No ingress is opened by default. Managed
ingress rules must have unique source/port pairs, regardless of their keys. Managed
security groups allow all outbound IPv4 traffic. For existing groups only, set
`security_group.create = false`, supply nonempty `security_group.ids`, and omit
`ingress_rules`. This module does not modify existing groups.

IMDSv2 is mandatory (one-hop metadata limit). Root volumes are always encrypted
and deleted with the instance. Public IP assignment is opt-in; subnet routing
still determines reachability. Tags propagate to the instance, root volume, and
managed security group resources. AWS permissions for the selected AMI, network,
KMS key, and existing instance profile remain the caller's responsibility.

Outputs: `instance_id`, `instance_arn`, `private_ip`, `public_ip`,
`availability_zone`, `security_group_id` (null without a managed group), and
`security_group_ids` (all attached groups).

## Local validation

```sh
terraform init -backend=false
terraform validate
terraform test -json -verbose > /tmp/ec2-module-tests.jsonl
python3 tests/assert_plan.py /tmp/ec2-module-tests.jsonl
```

The suite uses a mocked AWS provider and the real upstream module. It does not
create AWS infrastructure. Terraform's verbose test state allows the companion
verifier to check nested instance and security group resources directly.
