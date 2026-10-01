module "ec2" {
  source = "../../modules/ec2"

  name = "example-ec2"
  config = {
    ami       = var.ami_id
    vpc_id    = var.vpc_id
    subnet_id = var.instance_subnet_id
    user_data = var.user_data
  }
  tags = { Environment = "example" }
}

output "instance_id" {
  description = "Created instance ID for use in another module or target registration."
  value       = module.ec2.instance_id
}
