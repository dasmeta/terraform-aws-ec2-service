mock_provider "aws" {}

variables {
  name = "example-alb"
  config = {
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  }
  target_groups = { web = { port = 8080 } }
}

run "default_name_matches_alb" {
  command = plan
  assert {
    condition     = module.this.target_groups["web"].name == "example-alb"
    error_message = "An omitted target-group name must use the exact ALB name."
  }
}
run "custom_name" {
  command = plan
  variables { target_groups = { web = { name = "custom-web", port = 8080 } } }
  assert {
    condition     = module.this.target_groups["web"].name == "custom-web"
    error_message = "An explicit name must reach the AWS target group."
  }
}
run "mixed_default_and_custom_names" {
  command = plan
  variables { target_groups = { web = { port = 8080 }, api = { name = "custom-api", port = 9000 } } }
  assert {
    condition     = module.this.target_groups["web"].name == "example-alb" && module.this.target_groups["api"].name == "custom-api"
    error_message = "Adding another named group must not change the default group's name."
  }
}
run "duplicate_defaults" {
  command = plan
  variables { target_groups = { web = { port = 8080 }, api = { port = 9000 } } }
  expect_failures = [var.target_groups]
}
run "custom_name_collides_with_default" {
  command = plan
  variables { target_groups = { web = { port = 8080 }, api = { name = "example-alb", port = 9000 } } }
  expect_failures = [var.target_groups]
}
run "invalid_characters" {
  command = plan
  variables { target_groups = { web = { name = "invalid_name", port = 8080 } } }
  expect_failures = [var.target_groups]
}
run "too_long" {
  command = plan
  variables { target_groups = { web = { name = "abcdefghijklmnopqrstuvwxyz1234567", port = 8080 } } }
  expect_failures = [var.target_groups]
}
run "empty_name" {
  command = plan
  variables { target_groups = { web = { name = "", port = 8080 } } }
  expect_failures = [var.target_groups]
}
run "null_name_uses_default" {
  command = plan
  variables { target_groups = { web = { name = null, port = 8080 } } }
  assert {
    condition     = module.this.target_groups["web"].name == "example-alb"
    error_message = "Explicit null must use the ALB name."
  }
}
