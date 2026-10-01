mock_provider "aws" {}

variables {
  name = "example-alb"
  config = {
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group = {
      name        = "example-alb-sg"
      description = "Public application entry point"
      egress_rules = {
        app = { port = 8000, referenced_security_group_id = "sg-0123456789abcdef0", description = "Application only" }
      }
    }
  }
}

run "restricted_egress" {
  command = apply
  assert {
    condition     = length(local.egress_rules) == 1 && local.egress_rules["app"].from_port == 8000 && local.egress_rules["app"].to_port == 8000 && local.egress_rules["app"].referenced_security_group_id == "sg-0123456789abcdef0" && local.egress_rules["app"].cidr_ipv4 == null
    error_message = "Explicit egress must replace all-IPv4 egress with only TCP 8000 to the backend SG."
  }
}
run "empty_egress_denies_all" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { egress_rules = {} } } }
  assert {
    condition     = length(local.egress_rules) == 0
    error_message = "An explicit empty map must not restore default egress."
  }
}
run "omitted_egress_keeps_default" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] } }
  assert {
    condition     = length(local.egress_rules) == 1 && local.egress_rules["ipv4"].ip_protocol == "-1" && local.egress_rules["ipv4"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "Omission must preserve the existing allow-all IPv4 default."
  }
}
run "invalid_egress_port" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { egress_rules = { app = { port = 0, referenced_security_group_id = "sg-0123456789abcdef0" } } } } }
  expect_failures = [var.config]
}
run "missing_destination" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { egress_rules = { app = { port = 8000 } } } } }
  expect_failures = [var.config]
}
run "both_destinations" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { egress_rules = { app = { port = 8000, cidr_ipv4 = "10.0.0.0/8", referenced_security_group_id = "sg-0123456789abcdef0" } } } } }
  expect_failures = [var.config]
}
run "invalid_cidr" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { egress_rules = { app = { port = 8000, cidr_ipv4 = "bad" } } } } }
  expect_failures = [var.config]
}
run "duplicate_egress" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { egress_rules = { a = { port = 8000, referenced_security_group_id = "sg-0123456789abcdef0" }, b = { port = 8000, referenced_security_group_id = "sg-0123456789abcdef0" } } } } }
  expect_failures = [var.config]
}
run "egress_on_existing_alb_sg_rejected" {
  command = plan
  variables { config = { vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false, ids = ["sg-0123456789abcdef0"], egress_rules = {} } } }
  expect_failures = [var.config]
}
