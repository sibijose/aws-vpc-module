locals {
  subnets = length(data.aws_availability_zones.available.names)
}

variable "project" {
  default = "demo"
}
variable "environment" {}
variable "vpc_cidr" {}
