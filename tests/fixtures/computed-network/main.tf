variable "external_groups" {
  type    = bool
  default = true
}
variable "computed_cidr" {
  type    = bool
  default = true
}
variable "computed_port" {
  type    = bool
  default = true
}

resource "terraform_data" "network" {
  input = { cidr = "10.0.0.0/8", port = 8000 }
}

module "service" {
  source = "../../.."

  ec2 = {
    name      = "example-compute"
    ami       = "ami-0123456789abcdef0"
    vpc_id    = "vpc-0123456789abcdef0"
    subnet_id = "subnet-0123456789abcdef0"
    security_group = {
      create = !var.external_groups
      ids    = var.external_groups ? ["sg-02222222222222222"] : []
    }
  }
  alb = {
    name       = "example-alb"
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group = {
      create              = !var.external_groups
      ids                 = var.external_groups ? ["sg-01111111111111111"] : []
      allowed_cidr_blocks = var.external_groups ? [] : [var.computed_cidr ? terraform_data.network.output.cidr : "10.0.0.0/8"]
    }
  }
  target_groups = {
    app = {
      port                    = var.computed_port ? terraform_data.network.output.port : 8000
      attach_created_instance = true
    }
  }
  listeners = { http = { port = 80, target_group_key = "app" } }
}

# External SG rules have static resource addresses and unknown values only.
resource "aws_vpc_security_group_ingress_rule" "client" {
  count             = var.external_groups ? 1 : 0
  security_group_id = "sg-01111111111111111"
  cidr_ipv4         = terraform_data.network.output.cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "backend" {
  count                        = var.external_groups ? 1 : 0
  security_group_id            = "sg-02222222222222222"
  referenced_security_group_id = "sg-01111111111111111"
  from_port                    = terraform_data.network.output.port
  to_port                      = terraform_data.network.output.port
  ip_protocol                  = "tcp"
}
