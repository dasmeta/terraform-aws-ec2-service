variable "region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region containing the supplied resources."
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID."
}

variable "alb_subnet_ids" {
  type        = list(string)
  description = "At least two existing subnets in different availability zones within the VPC."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 networks allowed to reach the ALB listeners."
}

variable "instance_ids" {
  type        = map(string)
  description = "Existing EC2 instance IDs keyed by stable logical names, e.g. web_a and web_b."
}
