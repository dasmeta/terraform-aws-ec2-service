mock_provider "aws" {}

run "sensitive_bootstrap" {
  command = plan
  variables {
    ec2 = {
      name      = "example-compute"
      ami       = "ami-0123456789abcdef0"
      vpc_id    = "vpc-0123456789abcdef0"
      subnet_id = "subnet-0123456789abcdef0"
      user_data = sensitive("#!/bin/sh\necho mock-bootstrap-value >/tmp/bootstrap")
    }
    alb = {
      name       = "example-alb"
      vpc_id     = "vpc-0123456789abcdef0"
      subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    }
    target_groups = { app = { port = 8000, attach_created_instance = true } }
  }
  assert {
    condition     = issensitive(var.ec2.user_data) && !issensitive(local.target_groups["app"].targets)
    error_message = "Bootstrap data must remain sensitive without tainting target registration keys."
  }
}
