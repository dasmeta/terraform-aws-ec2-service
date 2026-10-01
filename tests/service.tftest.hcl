mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_resource "aws_instance" {
    defaults = {
      id  = "i-0123456789abcdef0"
      arn = "arn:aws:ec2:eu-central-1:123456789012:instance/i-0123456789abcdef0"
    }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/app/example/1234567890123456" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:targetgroup/example/1234567890123456" }
  }
}


run "disabled" {
  command = plan
  assert {
    condition     = output.instance_id == null && output.alb_arn == null && length(module.ec2) == 0 && length(module.alb) == 0
    error_message = "Omitting both components must create no infrastructure."
  }
}

run "ec2_only" {
  command = plan
  variables {
    ec2 = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
  }
  assert {
    condition     = length(module.ec2) == 1 && length(module.alb) == 0 && length(aws_vpc_security_group_ingress_rule.alb) == 0
    error_message = "EC2 alone must not create ALB or ALB ingress."
  }
}

run "alb_only_existing" {
  command = plan
  variables {
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 8080, targets = { existing = { instance_id = "i-0123456789abcdef1" } } } }
    listeners     = { http = { port = 80, target_group_key = "web" } }
  }
  assert {
    condition     = length(module.ec2) == 0 && length(module.alb) == 1 && length(aws_vpc_security_group_ingress_rule.alb) == 0
    error_message = "Existing EC2 targets must not create instances or modify existing security groups."
  }
}

run "combined_unknown_id_plan" {
  command = plan
  variables {
    ec2 = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
    alb = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = {
      web = { port = 8080, attach_created_instance = true, health_check = { port = "9090" } }
      api = { name = "example-api", port = 8000, attach_created_instance = true, created_instance_port = 8080, targets = { existing = { instance_id = "i-0123456789abcdef1" } } }
    }
    listeners = { http = { port = 80, target_group_key = "web" }, api = { port = 81, target_group_key = "api" } }
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb) == 2 && toset([for rule in aws_vpc_security_group_ingress_rule.alb : rule.from_port]) == toset([8080, 9090])
    error_message = "Managed ingress must deduplicate service ports and include the health-check port."
  }
}

run "combined_id_wiring" {
  command = apply
  variables {
    ec2           = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 8080, attach_created_instance = true, targets = { existing = { instance_id = "i-0123456789abcdef1" } } } }
    listeners     = { http = { port = 80, target_group_key = "web" } }
  }
  assert {
    condition     = local.target_groups["web"].targets["__created_instance"].instance_id == output.instance_id && length(local.target_groups["web"].targets) == 2
    error_message = "Managed and existing instances must coexist in the same target group."
  }
  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.alb : rule.security_group_id == module.ec2[0].security_group_id && rule.referenced_security_group_id == module.alb[0].security_group_id && rule.cidr_ipv4 == null])
    error_message = "Backend ingress must reference ALB security group, never a public CIDR."
  }
}

run "managed_reference_without_ec2" {
  command = plan
  variables {
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 80, attach_created_instance = true } }
  }
  expect_failures = [var.target_groups]
}
run "groups_without_alb" {
  command = plan
  variables { target_groups = { web = { port = 80 } } }
  expect_failures = [var.target_groups]
}
run "reserved_target_key" {
  command = plan
  variables {
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 80, targets = { __created_instance = { instance_id = "i-0123456789abcdef1" } } } }
  }
  expect_failures = [var.target_groups]
}
run "different_vpcs" {
  command = plan
  variables {
    ec2           = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef1", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 80, attach_created_instance = true } }
  }
  expect_failures = [var.target_groups]
}

run "existing_alb_security_groups" {
  command = plan
  variables {
    ec2           = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false, ids = ["sg-0123456789abcdef0"] } }
    target_groups = { web = { port = 8080, attach_created_instance = true } }
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb) == 1 && alltrue([for rule in aws_vpc_security_group_ingress_rule.alb : rule.referenced_security_group_id == "sg-0123456789abcdef0"])
    error_message = "Existing ALB security groups must be usable as ingress sources."
  }
}
run "existing_ec2_security_group_untouched" {
  command = plan
  variables {
    ec2           = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0", security_group = { create = false, ids = ["sg-0123456789abcdef0"] } }
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 8080, attach_created_instance = true } }
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb) == 0
    error_message = "Consumer-managed EC2 security groups must not be modified."
  }
}
run "listeners_without_alb" {
  command = plan
  variables { listeners = { http = { port = 80, target_group_key = "web" } } }
  expect_failures = [var.listeners]
}
run "managed_port_without_attachment" {
  command = plan
  variables {
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 80, created_instance_port = 8080 } }
  }
  expect_failures = [var.target_groups]
}

run "equivalent_health_check_ports" {
  command = plan
  variables {
    ec2           = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { port = 9090, attach_created_instance = true, health_check = { port = "09090" } } }
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb) == 1
    error_message = "Equivalent numeric service and health-check ports must not create duplicate ingress rules."
  }
}

run "duplicate_alb_source_groups" {
  command = plan
  variables {
    ec2           = { name = "example-compute", ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0" }
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false, ids = ["sg-0123456789abcdef0", "sg-0123456789abcdef0"] } }
    target_groups = { web = { port = 8080, attach_created_instance = true } }
  }
  expect_failures = [var.alb]
}

run "explicit_ingress_overlap" {
  command = plan
  variables {
    ec2 = { name = "example-compute",
      ami            = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { manual = { port = 8080, referenced_security_group_id = "sg-0123456789abcdef0" } } }
    }
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"], security_group = { create = false, ids = ["sg-0123456789abcdef0"] } }
    target_groups = { web = { port = 8080, attach_created_instance = true } }
  }
  expect_failures = [aws_vpc_security_group_ingress_rule.alb]
}

run "custom_target_group_name" {
  command = plan
  variables {
    alb           = { name = "example-service", vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"] }
    target_groups = { web = { name = "custom-service-web", port = 8080 } }
  }
  assert {
    condition     = local.target_groups["web"].name == "custom-service-web"
    error_message = "Root must preserve the optional target-group name for the ALB submodule."
  }
}
