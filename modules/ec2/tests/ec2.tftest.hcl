mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-09999999999999999" }
  }
  mock_resource "aws_instance" {
    defaults = {
      id                = "i-0123456789abcdef0"
      arn               = "arn:aws:ec2:eu-central-1:123456789012:instance/i-0123456789abcdef0"
      private_ip        = "10.0.1.10"
      public_ip         = "203.0.113.10"
      availability_zone = "eu-central-1a"
    }
  }
  mock_resource "aws_security_group" {
    defaults = {
      id  = "sg-0123456789abcdef0"
      arn = "arn:aws:ec2:eu-central-1:123456789012:security-group/sg-0123456789abcdef0"
    }
  }
}

variables {
  name = "test-service"
  config = {
    ami       = "ami-0123456789abcdef0"
    vpc_id    = "vpc-0123456789abcdef0"
    subnet_id = "subnet-0123456789abcdef0"
  }
  tags = { Environment = "test" }
}

run "secure_defaults" {
  command = apply

  assert {
    condition     = module.ec2_instance.ami == var.config.ami
    error_message = "The explicit AMI must be used."
  }
  assert {
    condition     = one(module.ec2_instance.root_block_device).encrypted && one(module.ec2_instance.root_block_device).volume_size == 20 && one(module.ec2_instance.root_block_device).volume_type == "gp3"
    error_message = "Root volume must default to encrypted 20 GiB gp3."
  }
  assert {
    condition     = output.instance_id == "i-0123456789abcdef0" && output.private_ip == "10.0.1.10" && output.availability_zone == "eu-central-1a"
    error_message = "Instance outputs must expose the created instance."
  }
  assert {
    condition     = output.security_group_id == "sg-0123456789abcdef0" && output.security_group_ids == tolist(["sg-0123456789abcdef0"])
    error_message = "Managed security group must be exposed."
  }
}

run "custom_options" {
  command = apply
  variables {
    config = {
      ami                         = "ami-0123456789abcdef0"
      vpc_id                      = "vpc-0123456789abcdef0"
      subnet_id                   = "subnet-0123456789abcdef0"
      instance_type               = "t3.small"
      key_name                    = "operator-key"
      iam_instance_profile        = "service-profile"
      user_data                   = "#!/bin/sh\necho ready"
      associate_public_ip_address = true
      monitoring                  = false
      root_volume = {
        size       = 40
        type       = "gp2"
        kms_key_id = "arn:aws:kms:eu-central-1:123456789012:key/12345678-1234-1234-1234-123456789012"
      }
      security_group = {
        ids = ["sg-09999999999999999"]
        ingress_rules = {
          web = { port = 8080, cidr_ipv4 = "10.0.0.0/8", description = "Private web" }
          alb = { port = 8081, referenced_security_group_id = "sg-08888888888888888" }
        }
      }
    }
  }
  assert {
    condition     = one(module.ec2_instance.root_block_device).volume_size == 40 && one(module.ec2_instance.root_block_device).volume_type == "gp2" && one(module.ec2_instance.root_block_device).kms_key_id == var.config.root_volume.kms_key_id
    error_message = "Root volume overrides must reach the instance."
  }
  assert {
    condition     = toset(output.security_group_ids) == toset(["sg-0123456789abcdef0", "sg-09999999999999999"])
    error_message = "Both existing and managed security groups must be returned."
  }
  assert {
    condition     = output.instance_arn == "arn:aws:ec2:eu-central-1:123456789012:instance/i-0123456789abcdef0" && output.public_ip == "203.0.113.10"
    error_message = "ARN and public IP outputs must be forwarded."
  }
}

run "existing_security_groups" {
  command = apply
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { create = false, ids = ["sg-09999999999999999"] }
    }
  }
  assert {
    condition     = output.security_group_id == null && output.security_group_ids == tolist(["sg-09999999999999999"])
    error_message = "Existing-only mode must not create a security group."
  }
}

run "invalid_name" {
  command = plan
  variables { name = " " }
  expect_failures = [var.name]
}

run "invalid_empty_ami" {
  command = plan
  variables {
    config = {
      vpc_id    = "vpc-0123456789abcdef0"
      subnet_id = "subnet-0123456789abcdef0"
      ami       = ""
    }
  }
  expect_failures = [var.config]
}

run "invalid_root_size" {
  command = plan
  variables {
    config = {
      ami         = "ami-0123456789abcdef0"
      vpc_id      = "vpc-0123456789abcdef0"
      subnet_id   = "subnet-0123456789abcdef0"
      root_volume = { size = 0 }
    }
  }
  expect_failures = [var.config]
}

run "invalid_fractional_root_size" {
  command = plan
  variables {
    config = {
      ami         = "ami-0123456789abcdef0"
      vpc_id      = "vpc-0123456789abcdef0"
      subnet_id   = "subnet-0123456789abcdef0"
      root_volume = { size = 1.5 }
    }
  }
  expect_failures = [var.config]
}

run "invalid_root_type" {
  command = plan
  variables {
    config = {
      ami         = "ami-0123456789abcdef0"
      vpc_id      = "vpc-0123456789abcdef0"
      subnet_id   = "subnet-0123456789abcdef0"
      root_volume = { type = "io2" }
    }
  }
  expect_failures = [var.config]
}

run "invalid_port_zero" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { bad = { port = 0, cidr_ipv4 = "10.0.0.0/8" } } }
    }
  }
  expect_failures = [var.config]
}

run "invalid_port_high" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { bad = { port = 65536, cidr_ipv4 = "10.0.0.0/8" } } }
    }
  }
  expect_failures = [var.config]
}

run "invalid_port_fractional" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { bad = { port = 80.5, cidr_ipv4 = "10.0.0.0/8" } } }
    }
  }
  expect_failures = [var.config]
}

run "invalid_missing_source" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { bad = { port = 80 } } }
    }
  }
  expect_failures = [var.config]
}

run "invalid_both_sources" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { bad = { port = 80, cidr_ipv4 = "10.0.0.0/8", referenced_security_group_id = "sg-09999999999999999" } } }
    }
  }
  expect_failures = [var.config]
}

run "invalid_cidr" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { bad = { port = 80, cidr_ipv4 = "not-a-cidr" } } }
    }
  }
  expect_failures = [var.config]
}

run "invalid_ipv6" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = { bad = { port = 80, cidr_ipv4 = "::/0" } } }
    }
  }
  expect_failures = [var.config]
}

run "invalid_disabled_without_ids" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { create = false }
    }
  }
  expect_failures = [var.config]
}

run "invalid_disabled_with_ingress" {
  command = plan
  variables {
    config = {
      ami            = "ami-0123456789abcdef0"
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_id      = "subnet-0123456789abcdef0"
      security_group = { create = false, ids = ["sg-09999999999999999"], ingress_rules = { bad = { port = 80, cidr_ipv4 = "10.0.0.0/8" } } }
    }
  }
  expect_failures = [var.config]
}

run "duplicate_ingress" {
  command = plan
  variables {
    config = {
      ami = "ami-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0", subnet_id = "subnet-0123456789abcdef0"
      security_group = { ingress_rules = {
        first  = { port = 8080, cidr_ipv4 = "10.0.0.0/8" }
        second = { port = 8080, cidr_ipv4 = "10.0.0.0/8" }
      } }
    }
  }
  expect_failures = [var.config]
}
