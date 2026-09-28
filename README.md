# terraform-aws-ec2-service

Terraform modules for an EC2 service behind an Application Load Balancer. Use
`modules/ec2` and `modules/alb` independently, or use the root module to connect
new and existing instances to the same ALB.

Requires Terraform `~> 1.9` and AWS provider `~> 6.37`. Configure the AWS provider
in the calling configuration. The wrappers pin upstream
[EC2 instance 6.4.0](https://github.com/terraform-aws-modules/terraform-aws-ec2-instance/tree/v6.4.0)
and [ALB 10.5.1](https://github.com/terraform-aws-modules/terraform-aws-alb/tree/v10.5.1).

## New EC2 + ALB

This example assumes the repository is checked out at `./terraform-aws-ec2-service`.
Replace the sample IDs with resources from your account and region.

```hcl
module "service" {
  source = "./terraform-aws-ec2-service"

  ec2 = {
    name      = "example-compute"
    ami       = "ami-0123456789abcdef0"
    vpc_id    = "vpc-0123456789abcdef0"
    subnet_id = "subnet-0123456789abcdef0"
  }
  alb = {
    name       = "example-service"
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group = { allowed_cidr_blocks = ["10.0.0.0/8"] }
  }
  target_groups = {
    web = {
      port                    = 8080
      attach_created_instance = true
      health_check            = { path = "/health" }
    }
  }
  listeners = {
    http = { port = 80, target_group_key = "web" }
  }
  tags = { Environment = "example" }
}
```

The new instance ID is passed to the target registration in the same operation.
The root adds ingress from the ALB security group to its managed EC2 security
group on the target and health-check ports. Install/start the application with
`ec2.user_data`, a prepared AMI, or your application deployment process.

## Independent components

| Need | Module / example |
| --- | --- |
| One EC2, no ALB | [modules/ec2](modules/ec2/README.md), [example](examples/ec2-only) |
| ALB for existing EC2 instances | [modules/alb](modules/alb/README.md), [example](examples/alb-existing-ec2) |
| EC2 and ALB together | Root module, [example](examples/complete) |
| Multiple groups/instances, HTTPS and redirects | [example](examples/multiple-target-groups) |

The root also supports EC2-only by omitting `alb`, and ALB-only by omitting
`ec2`. Omitting both creates no resources. A direct EC2 submodule call manages
one instance; use `for_each` around it for multiple instances.

## Root inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `ec2` | `null` | Required `name` plus [EC2 config](modules/ec2/README.md); null disables EC2 |
| `alb` | `null` | Required `name` plus [ALB config](modules/alb/README.md); null disables ALB |
| `target_groups` | `{}` | [ALB target groups](modules/alb/README.md), plus the two fields below |
| `listeners` | `{}` | [HTTP/HTTPS listeners](modules/alb/README.md) |
| `backend_ingress_rules` | `{}` | Explicit additive TCP ingress on existing backend SGs, sourced from the ALB |
| `tags` | `{}` | Common resource tags |

Set `ec2.name` and `alb.name` independently for enabled components. ALB names
must be 1–32 alphanumeric/hyphen characters, without leading/trailing hyphens or
the `internal-` prefix. There is no shared root `name` input. To migrate an earlier
root configuration, move its `name` into each enabled component; keep the values
unchanged to preserve resource names. Direct submodule calls still use their own
`name` argument alongside `config`.

Each target group accepts an optional `name`. Without it (or with `null`), the
AWS target group name equals `alb.name`. To override it:

```yaml
target_groups:
  app:
    name: example-app-targets
    port: 8000
```

For multiple groups, set distinct names for the additional groups; at most one
may use the default ALB name. Group map keys used by listeners remain unchanged.
Names must be 1–32 alphanumeric/hyphen characters, without leading/trailing
hyphens. See [target group naming and replacement](modules/alb/README.md#target-groups)
before renaming an existing group or changing a replacement-triggering property.

Each root target group additionally accepts:

- `attach_created_instance` (default `false`): register the root-created instance.
- `created_instance_port` (default `null`): override its target port; requires
  `attach_created_instance = true` and otherwise inherits the group's port.

Existing targets may be supplied together with the created instance:

```hcl
target_groups = {
  web = {
    port                    = 8080
    attach_created_instance = true
    targets = {
      existing_a = { instance_id = "i-0123456789abcdef1" }
      existing_b = { instance_id = "i-0123456789abcdef2", port = 8081 }
    }
  }
}
```

Use stable logical keys for groups and targets, including when IDs come from
other modules. Do not use generated instance IDs as map keys. The target key
`__created_instance` is reserved by the root. Duplicate instance/effective-port
pairs within one group are rejected. An instance may be in several groups or
registered on several ports. Empty groups and an ALB with no listeners are valid
for staged provisioning.

## Network and lifecycle ownership

- Supply existing VPC/subnets; ALB subnets must span at least two availability
  zones. Instance targets must be in the ALB VPC. The root checks configured VPC
  equality for its managed instance; AWS checks actual subnet/instance placement.
- EC2 defaults: no public IP, encrypted gp3 root disk, required IMDSv2, detailed
  monitoring, no inbound rules. Outbound IPv4 is allowed on generated groups.
- ALB defaults: internal, IPv4, deletion protection enabled. Listener ingress
  opens only to explicit `allowed_cidr_blocks`; the empty default allows none.
  For a public ALB set `internal = false`, supply public subnets and explicit CIDRs.
- Both components create a security group by default and accept additional
  existing groups. Setting `security_group.create = false` requires existing IDs.
- Existing EC2 instances and security groups are never imported or recreated.
  Existing groups are untouched by default. To add ALB access explicitly, use
  `backend_ingress_rules` below, or manage the rules externally. Permit application
  **and health-check ports**. Registration alone does not make a target healthy.
- The root automatically adds connection rules to its own created EC2 security
  group. With a consumer-managed EC2 group, use explicit rules. With existing ALB
  groups only, root rules reference each supplied ALB group. Group IDs must be
  unique. Do not duplicate automatic ALB ingress in explicit EC2 ingress rules;
  the root rejects overlapping source/port pairs.
- Removing a target registration deregisters it without terminating the EC2.
  Removing `ec2` from a root configuration destroys the instance it manages.
  Before destroying an ALB, set `enable_deletion_protection = false` and apply it.
- HTTPS requires an existing certificate ARN in the ALB region. VPC creation,
  certificate issuance, DNS, ASGs, host/path listener rules and application
  deployment are outside this module's scope.

## Explicit access to an existing backend

The root can manage the two sides of the connection without managing the existing
instance or security group's lifecycle:

```hcl
alb = {
  name       = "example-service"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  security_group = {
    allowed_cidr_blocks = ["0.0.0.0/0"]
    egress_rules = {
      app = { port = 8000, referenced_security_group_id = "sg-0123456789abcdef0" }
    }
  }
}
backend_ingress_rules = {
  app = {
    security_group_id = "sg-0123456789abcdef0"
    port              = 8000
    description       = "Application traffic from ALB"
  }
}
```

`backend_ingress_rules` is root-only and defaults to `{}`. Each stable map key
creates one TCP rule per ALB source SG. Only these explicit rules are managed;
existing VPN/other rules are preserved. Removing a map entry removes its managed
rule. Do not manage the same rule through another workspace/module, or through
inline SG rules that authoritatively own all ingress. Import any already-existing
rule into its chosen owner before applying a source-module migration.

`egress_rules = null` (or omission) retains all outbound IPv4; an explicit map
replaces that default. `{}` permits no outbound connections. Include both service
and health-check ports when they differ. Each rule requires `port` and exactly one
of `cidr_ipv4` or `referenced_security_group_id`, with optional `description`.
The ALB group must be module-created to configure egress this way.

Migrating from direct upstream modules changes Terraform resource addresses and
may require state moves/imports to avoid recreation. Review the real plan before
applying; local mock tests do not migrate an existing deployment.

## Outputs

`instance_id`, `instance_arn`, `instance_private_ip`, `instance_public_ip`,
`instance_security_group_ids`, `alb_arn`, `alb_dns_name`, `alb_zone_id`,
`alb_security_group_ids`, `listener_arns`, and `target_group_arns`.

Disabled components return null scalar outputs and empty maps/lists. Listener and
target group ARN maps preserve the input keys. Use `alb_dns_name` and `alb_zone_id`
for a separately managed DNS alias.

## Verification

```sh
./scripts/validate.sh
```

The script initializes and validates the root, both submodules and all examples,
then runs native Terraform tests with a mocked AWS provider and checks the real
nested upstream resources in test plans/states. Requires Terraform, Python 3,
and network access to download public module/provider dependencies. No AWS
credentials or live infrastructure are used by these tests.

Mocks validate configuration, dependency ordering and resource wiring. Verify
real AMI compatibility, IAM permissions, subnet placement, application health,
network routes and TLS certificates in your deployment environment. Upstream
EC2 also reads public AMI SSM metadata and the supplied subnet during real plans,
even when the AMI/VPC are explicit.

Design and implementation evidence: [specification](specs/001-ec2-alb-service/spec.md),
[plan](specs/001-ec2-alb-service/plan.md), [tasks](specs/001-ec2-alb-service/tasks.md).
