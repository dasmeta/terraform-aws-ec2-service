mock_provider "aws" {
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:targetgroup/example/0123456789abcdef" }
  }
}
variables {
  ec2 = {
    name      = "example-compute"
    ami       = "ami-0123456789abcdef0"
    vpc_id    = "vpc-0123456789abcdef0"
    subnet_id = "subnet-0123456789abcdef0"
  }
  alb = {
    name       = "example-alb"
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group = {
      create = false
      ids    = ["sg-02222222222222222", "sg-03333333333333333"]
    }
  }
  target_groups         = { app = { port = 8000, attach_created_instance = true } }
  backend_ingress_rules = { external = { security_group_id = "sg-04444444444444444", port = 8000 } }
}
run "source_identity_initial" {
  command = apply
}
run "source_identity_unchanged" {
  command = plan
}
run "source_identity_reordered" {
  command = plan
  variables {
    alb = {
      name       = "example-alb"
      vpc_id     = "vpc-0123456789abcdef0"
      subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group = {
        create = false
        ids    = ["sg-03333333333333333", "sg-02222222222222222"]
      }
    }
  }
}
run "source_identity_inserted" {
  command = plan
  variables {
    alb = {
      name       = "example-alb"
      vpc_id     = "vpc-0123456789abcdef0"
      subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group = {
        create = false
        ids    = ["sg-01111111111111111", "sg-02222222222222222", "sg-03333333333333333"]
      }
    }
  }
}
