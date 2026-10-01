mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/app/example/1234567890123456"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:targetgroup/example/1234567890123456"
    }
  }
}

variables {
  name = "example-alb"
  config = {
    vpc_id         = "vpc-0123456789abcdef0"
    subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group = { allowed_cidr_blocks = ["10.0.0.0/8"] }
  }
  target_groups = {
    web = {
      port = 8080
      targets = {
        first  = { instance_id = "i-0123456789abcdef0" }
        second = { instance_id = "i-0123456789abcdef1", port = 8081 }
      }
    }
    empty = { name = "example-empty", port = 9000 }
  }
  listeners = { http = { port = 80, target_group_key = "web" } }
}

run "existing_targets_and_empty_group" {
  command = apply
  assert {
    condition     = length(module.this.target_groups) == 2 && module.this.target_groups["empty"].target_type == "instance"
    error_message = "Both populated and empty instance target groups must be supported."
  }
  assert {
    condition     = local.target_group_attachments[jsonencode(["web", "first"])].port == 8080 && local.target_group_attachments[jsonencode(["web", "second"])].port == 8081
    error_message = "Attachments must inherit the group port, with per-target overrides."
  }
  assert {
    condition     = module.this.listeners["http"].default_action[0].target_group_arn == module.this.target_groups["web"].arn
    error_message = "Listener must forward to its selected target group."
  }
}

run "remove_registration" {
  command = apply
  variables {
    target_groups = { web = { port = 8080, targets = { first = { instance_id = "i-0123456789abcdef0" } } }, empty = { name = "example-empty", port = 9000 } }
  }
  assert {
    condition     = length(local.target_group_attachments) == 1 && output.target_group_arns["web"] == run.existing_targets_and_empty_group.target_group_arns["web"]
    error_message = "Removing a target must keep the target group identity stable."
  }
}

run "https_and_redirect" {
  command = plan
  variables {
    listeners = {
      http  = { port = 80, redirect_to_https = true }
      https = { port = 443, protocol = "HTTPS", certificate_arn = "arn:aws:acm:eu-central-1:123456789012:certificate/12345678-1234-1234-1234-123456789012", target_group_key = "web" }
    }
  }
  assert {
    condition     = module.this.listeners["http"].default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "HTTP must redirect to HTTPS."
  }
}

run "invalid_group_reference" {
  command = plan
  variables { listeners = { http = { port = 80, target_group_key = "missing" } } }
  expect_failures = [var.listeners]
}
run "missing_certificate" {
  command = plan
  variables { listeners = { https = { port = 443, protocol = "HTTPS", target_group_key = "web" } } }
  expect_failures = [var.listeners]
}
run "invalid_protocol" {
  command = plan
  variables { target_groups = { web = { port = 80, protocol = "TCP" } } }
  expect_failures = [var.target_groups]
}
run "invalid_port" {
  command = plan
  variables { target_groups = { web = { port = 65536 } } }
  expect_failures = [var.target_groups]
}
run "invalid_listener_port" {
  command = plan
  variables { listeners = { http = { port = 0, target_group_key = "web" } } }
  expect_failures = [var.listeners]
}
run "duplicate_targets" {
  command = plan
  variables {
    target_groups = { web = { port = 8080, targets = { a = { instance_id = "i-0123456789abcdef0" }, b = { instance_id = "i-0123456789abcdef0", port = 8080 } } } }
  }
  expect_failures = [var.target_groups]
}
run "too_few_subnets" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0"] } }
  expect_failures = [var.config]
}
run "invalid_health_check_port" {
  command = plan
  variables { target_groups = { web = { port = 8080, health_check = { port = "0" } } } }
  expect_failures = [var.target_groups]
}
run "redirect_without_https" {
  command = plan
  variables { listeners = { http = { port = 80, redirect_to_https = true } } }
  expect_failures = [var.listeners]
}
run "existing_security_groups" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false, ids = ["sg-0123456789abcdef0"] } } }
  assert {
    condition     = output.security_group_id == null && output.security_group_ids == tolist(["sg-0123456789abcdef0"])
    error_message = "Existing groups must be used without a managed security group."
  }
}

run "empty_alb" {
  command = plan
  variables {
    target_groups = {}
    listeners     = {}
  }
  assert {
    condition     = length(module.this.listeners) == 0 && length(module.this.target_groups) == 0 && length(local.target_group_attachments) == 0
    error_message = "An ALB may be provisioned before listeners and targets."
  }
}
run "fractional_target_port" {
  command = plan
  variables { target_groups = { web = { port = 8080, targets = { a = { instance_id = "i-0123456789abcdef0", port = 80.5 } } } } }
  expect_failures = [var.target_groups]
}
run "malformed_health_check_port" {
  command = plan
  variables { target_groups = { web = { port = 8080, health_check = { port = "wrong" } } } }
  expect_failures = [var.target_groups]
}
run "invalid_health_timing" {
  command = plan
  variables { target_groups = { web = { port = 8080, health_check = { interval = 5, timeout = 10 } } } }
  expect_failures = [var.target_groups]
}
run "invalid_listener_protocol" {
  command = plan
  variables { listeners = { http = { port = 80, protocol = "TCP", target_group_key = "web" } } }
  expect_failures = [var.listeners]
}
run "duplicate_listener_port" {
  command = plan
  variables { listeners = { first = { port = 80, target_group_key = "web" }, second = { port = 80, target_group_key = "web" } } }
  expect_failures = [var.listeners]
}
run "invalid_cidr" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { allowed_cidr_blocks = ["::/0"] } } }
  expect_failures = [var.config]
}
run "missing_existing_group" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false } } }
  expect_failures = [var.config]
}
run "empty_target_id" {
  command = plan
  variables { target_groups = { web = { port = 8080, targets = { invalid = { instance_id = "" } } } } }
  expect_failures = [var.target_groups]
}
