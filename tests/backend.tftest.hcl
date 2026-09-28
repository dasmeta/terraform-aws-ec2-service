mock_provider "aws" {
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:targetgroup/example/0123456789abcdef" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-03333333333333333" }
  }
}
variables {
  alb = { name = "example-service",
    vpc_id                     = "vpc-0123456789abcdef0"
    subnet_ids                 = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    internal                   = false
    idle_timeout               = 300
    enable_deletion_protection = false
    security_group = {
      name                = "example-service-alb"
      description         = "Public application entry point"
      allowed_cidr_blocks = ["0.0.0.0/0"]
      egress_rules        = { app = { port = 8000, referenced_security_group_id = "sg-0123456789abcdef0" } }
    }
  }
  backend_ingress_rules = {
    app = { security_group_id = "sg-0123456789abcdef0", port = 8000, description = "Application traffic from ALB" }
  }
}
run "existing_backend_opt_in" {
  command = apply
  assert {
    condition     = length(module.ec2) == 0 && length(aws_vpc_security_group_ingress_rule.backend) == 1 && length(aws_vpc_security_group_ingress_rule.alb) == 0
    error_message = "Explicit existing-SG ingress must not create an instance or take over its SG."
  }
  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.backend : rule.security_group_id == "sg-0123456789abcdef0" && rule.referenced_security_group_id == output.alb_security_group_ids[0] && rule.from_port == 8000 && rule.to_port == 8000 && rule.ip_protocol == "tcp" && rule.cidr_ipv4 == null])
    error_message = "Only the requested SG must accept TCP 8000 from the ALB SG."
  }
}
run "no_opt_in_no_changes" {
  command = plan
  variables { backend_ingress_rules = {} }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.backend) == 0
    error_message = "Existing groups must remain untouched without explicit opt-in."
  }
}
run "backend_without_alb" {
  command = plan
  variables { alb = null }
  expect_failures = [var.backend_ingress_rules]
}
run "invalid_backend_port" {
  command = plan
  variables { backend_ingress_rules = { app = { security_group_id = "sg-0123456789abcdef0", port = 65536 } } }
  expect_failures = [var.backend_ingress_rules]
}
run "empty_backend_group" {
  command = plan
  variables { backend_ingress_rules = { app = { security_group_id = "", port = 8000 } } }
  expect_failures = [var.backend_ingress_rules]
}
run "duplicate_backend_rules" {
  command = plan
  variables { backend_ingress_rules = { a = { security_group_id = "sg-0123456789abcdef0", port = 8000 }, b = { security_group_id = "sg-0123456789abcdef0", port = 8000 } } }
  expect_failures = [var.backend_ingress_rules]
}
run "existing_alb_source_groups" {
  command = plan
  variables { alb = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false, ids = ["sg-01111111111111111", "sg-02222222222222222"] } } }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.backend) == 2 && toset([for rule in aws_vpc_security_group_ingress_rule.backend : rule.referenced_security_group_id]) == toset(["sg-01111111111111111", "sg-02222222222222222"])
    error_message = "Explicit backend rules must support supplied ALB groups using stable keys."
  }
}

run "overlap_with_automatic_ec2_ingress" {
  command = apply
  variables {
    ec2                   = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
    target_groups         = { app = { port = 8000, attach_created_instance = true } }
    backend_ingress_rules = { duplicate = { security_group_id = "sg-03333333333333333", port = 8000 } }
  }
  expect_failures = [aws_vpc_security_group_ingress_rule.backend]
}
run "overlap_with_explicit_ec2_ingress" {
  command = plan
  variables {
    ec2 = { name = "example-compute",
      ami            = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { manual = { port = 8000, referenced_security_group_id = "sg-01111111111111111" } } }
    }
    alb                   = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false, ids = ["sg-01111111111111111"] } }
    backend_ingress_rules = { duplicate = { security_group_id = "sg-03333333333333333", port = 8000 } }
  }
  expect_failures = [aws_vpc_security_group_ingress_rule.backend]
}
