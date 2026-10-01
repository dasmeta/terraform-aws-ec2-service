variable "region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region containing the supplied resources."
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID."
}

variable "ami_id" {
  type        = string
  description = "AMI ID compatible with t3.micro (x86_64) in the selected region."
}

variable "instance_subnet_id" {
  type        = string
  description = "Existing subnet for the EC2 instance."
}

variable "user_data" {
  type        = string
  default     = null
  description = "Optional startup script; install/run your application on the configured target port."
}

variable "alb_subnet_ids" {
  type        = list(string)
  description = "At least two existing subnets in different availability zones within the VPC."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 networks allowed to reach the ALB listeners."
}
