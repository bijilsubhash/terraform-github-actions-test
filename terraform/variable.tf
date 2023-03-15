variable "aws_region" {
  default = "ap-southeast-2"
}

variable "vpc_cidr" {
  default = "10.20.0.0/16"
}

variable "public_subnets_cidr" {
  type    = list(any)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnets_cidr" {
  type    = list(any)
  default = ["10.20.3.0/24", "10.20.4.0/24"]
}

variable "azs" {
  type    = list(any)
  default = ["ap-southeast-2a", "ap-southeast-2b"]
}