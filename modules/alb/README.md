# ALB submodule

Creates an Application Load Balancer, optional security group, listeners, instance
target groups, and target registrations through upstream ALB `10.5.1`.
Existing instances and security groups remain consumer-managed.

```hcl
module "alb" {
  source = "./terraform-aws-ec2-service/modules/alb"

  name = "example-alb"
  config = {
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group = { allowed_cidr_blocks = ["10.0.0.0/8"] }
  }
  target_groups = {
    web = {
      port = 8080
      targets = {
        first  = { instance_id = "i-0123456789abcdef0" }
        second = { instance_id = "i-0123456789abcdef1", port = 8081 }
      }
      health_check = { path = "/health" }
    }
  }
  listeners = { http = { port = 80, target_group_key = "web" } }
}
```

Inputs are `name`, `config`, `target_groups` (default `{}`), `listeners` (default
`{}`), and `tags` (default `{}`). The caller configures the AWS provider.
Terraform `~> 1.9` and AWS provider `~> 6.37` are required.

## ALB configuration

| `config` field | Default / requirement |
| --- | --- |
| `vpc_id` | Required existing VPC ID |
| `subnet_ids` | Required; at least two distinct subnets in different AZs |
| `internal` | `true` |
| `enable_deletion_protection` | `true` |
| `idle_timeout` | `60` seconds; 1–4000 |
| `security_group.create` | `true` |
| `security_group.name` / `description` | `null`; optional generated SG name prefix and description |
| `security_group.egress_rules` | `null`; allow all IPv4 by default, explicit map replaces this default |
| `security_group.ids` | `[]`; additional existing groups, required if creation disabled |
| `security_group.allowed_cidr_blocks` | `[]`; IPv4 sources allowed on listener ports, generated group only |

The generated group allows all outbound IPv4 traffic unless `egress_rules` is
specified. An explicit `{}` allows no egress. Entries are keyed TCP rules with
`port` and exactly one destination (`cidr_ipv4` or `referenced_security_group_id`),
plus optional `description`. For example:

```hcl
security_group = {
  name        = "example-alb"
  description = "Application entry point"
  allowed_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = {
    app = { port = 8000, referenced_security_group_id = "sg-0123456789abcdef0" }
  }
}
```

Custom egress requires a module-created group. The optional `name` retains
upstream's name-prefix behavior, with an AWS/provider-generated suffix.
No inbound traffic is
allowed until CIDRs are supplied. Existing group rules are never changed. For
public ingress, set `internal = false`, choose public subnets, and provide the
allowed CIDRs explicitly. ALBs and target groups use IPv4.

## Target groups

| Group field | Default / requirement |
| --- | --- |
| `name` | ALB name; optional explicit AWS target group name |
| `port` | Required; integer 1–65535 |
| `protocol` | `HTTP`; accepts HTTP/HTTPS |
| `deregistration_delay` | `300` seconds; 0–3600 |
| `targets` | `{}`; map of logical keys to `{ instance_id, port? }` |
| `health_check.path` | `/` |
| `health_check.port` | `traffic-port`; or a numeric port string |
| `health_check.protocol` | `HTTP`; accepts HTTP/HTTPS |
| `health_check.matcher` | `200-399` |
| `health_check.interval` / `timeout` | `30` / `5` seconds; timeout must be less than interval |
| `health_check.healthy_threshold` / `unhealthy_threshold` | `3` / `3`; integers 2–10 |

If `name` is omitted or null, the target group uses the exact ALB name. For
multiple groups, give the additional groups distinct names; at most one group
can use the ALB name. Names remain stable when other groups are added or removed.
Map keys still identify listener references and attachments independently of the
AWS name. The `Name` tag matches the effective target group name.

Names must be unique per AWS account/region and contain 1–32 alphanumeric or
hyphen characters, without leading/trailing hyphens ([AWS naming rules](https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_CreateTargetGroup.html)).
The module rejects duplicate effective names within its configuration.

Changing a deployed target group's name replaces it. Upgrading from the earlier
auto-generated naming behavior also replaces that group. Upstream uses
create-before-destroy: when changing another property that requires replacement
(e.g. protocol or port), supply a new name so the replacement can coexist with
the old target group during the transition.

Every group uses instance targets. A target's optional port overrides the group
port. The same instance can serve multiple groups/ports; duplicate instance and
port pairs within one group are rejected. Empty groups are allowed. Keys must be
known during planning; instance IDs may be outputs from another module.

Use root `backend_ingress_rules` for explicit additive access, or open the existing EC2 security groups externally to `security_group_id` (or your supplied ALB
groups) on the effective service ports and health-check ports. Removing a target
only deregisters it. Actual instance/VPC compatibility and service health are
checked by AWS and the application deployment.

## Listeners

| Listener field | Default / requirement |
| --- | --- |
| `port` | Required; unique integer 1–65535 |
| `protocol` | `HTTP`; accepts HTTP/HTTPS |
| `target_group_key` | Required for forwarding; must match a group key |
| `certificate_arn` | Required for HTTPS, omitted for HTTP |
| `ssl_policy` | `ELBSecurityPolicy-TLS13-1-2-2021-06` for HTTPS |
| `redirect_to_https` | `false`; use on HTTP instead of `target_group_key` |
| `redirect_port` | `443`; must match a configured HTTPS listener |

```hcl
listeners = {
  http = { port = 80, redirect_to_https = true }
  https = {
    port             = 443
    protocol         = "HTTPS"
    certificate_arn  = "arn:aws:acm:eu-central-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    target_group_key = "web"
  }
}
```

The redirect uses HTTP 301. Host/path routing, weighted forwarding, WAF and DNS
are not exposed. See [multiple groups example](../../examples/multiple-target-groups).

Outputs: `alb_arn`, `alb_dns_name`, `alb_zone_id`, `security_group_id` (null without
a generated group), `security_group_ids`, `listener_arns`, and `target_group_arns`.

Run the repository's [validation script](../../scripts/validate.sh) for provider
schema checks and AWS mock tests. Real deployments require existing networking,
compatible instance targets, reachable application ports and valid certificates.
