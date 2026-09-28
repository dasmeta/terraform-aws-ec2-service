module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "6.4.0"

  name                        = var.name
  ami                         = var.config.ami
  instance_type               = var.config.instance_type
  subnet_id                   = var.config.subnet_id
  key_name                    = var.config.key_name
  iam_instance_profile        = var.config.iam_instance_profile
  user_data                   = var.config.user_data
  associate_public_ip_address = var.config.associate_public_ip_address
  monitoring                  = var.config.monitoring

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device = {
    encrypted             = true
    delete_on_termination = true
    size                  = var.config.root_volume.size
    type                  = var.config.root_volume.type
    kms_key_id            = var.config.root_volume.kms_key_id
  }

  create_security_group  = var.config.security_group.create
  security_group_vpc_id  = var.config.vpc_id
  vpc_security_group_ids = var.config.security_group.ids
  security_group_ingress_rules = {
    for key, rule in var.config.security_group.ingress_rules : key => {
      ip_protocol                  = "tcp"
      from_port                    = rule.port
      to_port                      = rule.port
      cidr_ipv4                    = rule.cidr_ipv4
      referenced_security_group_id = rule.referenced_security_group_id
      description                  = rule.description
    }
  }
  security_group_egress_rules = {
    ipv4 = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all IPv4 outbound traffic"
    }
  }

  tags = var.tags
}
