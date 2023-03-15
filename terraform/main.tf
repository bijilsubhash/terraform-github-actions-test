# Configuring terraform
terraform {
  backend "s3" {
    bucket         = "my-tf-test-bucket-324838239"
    key            = "demo_infrastructure/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

#intiiating the provider
provider "aws" {
  region = var.aws_region
}

#creating a vpc
resource "aws_vpc" "vpc_demo" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "vpc_demo"
  }
}

#creating public subnets
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets_cidr)
  vpc_id                  = aws_vpc.vpc_demo.id
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

#creating private subnets
resource "aws_subnet" "private" {
  count                   = length(var.private_subnets_cidr)
  vpc_id                  = aws_vpc.vpc_demo.id
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

#creating an internet gateway
resource "aws_internet_gateway" "vpc_gw" {
  vpc_id = aws_vpc.vpc_demo.id

  tags = {
    Name = "vpc_gw"
  }
}

#ec2 ami lookup
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

#initating public ec2 instances
resource "aws_instance" "public_ec2_demo" {
  count                  = length(aws_subnet.public[*].id)
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = element(aws_subnet.public[*].id, count.index)
  vpc_security_group_ids = [aws_security_group.sg.id]

  tags = {
    Name = "public_ec2_demo"
  }
}

#initiating private ec2 instances
resource "aws_instance" "private_ec2_demo" {
  count                  = length(aws_subnet.private[*].id)
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = element(aws_subnet.private[*].id, count.index)
  vpc_security_group_ids = [aws_security_group.sg.id]

  tags = {
    Name = "private_ec2_demo"
  }
}


#define route table for internet access
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc_demo.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_gw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

#route table association with public subnets
resource "aws_route_table_association" "route_table_association" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

#creating security group 
resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.vpc_demo.id
  # Inbound Rules
  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Outbound Rules
  # Internet access to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#creating elastic ip (fixed ip)
resource "aws_eip" "nat_gateway" {
  count = length(var.public_subnets_cidr)
  vpc   = true

  tags = {

    Name = "eip-${count.index + 1}"
  }
}

#creating nat on each public subnet
resource "aws_nat_gateway" "nat_gateway" {
  count         = length(var.public_subnets_cidr)
  allocation_id = element(aws_eip.nat_gateway[*].id, count.index)
  subnet_id     = element(aws_subnet.public[*].id, count.index)

  tags = {
    Name = "nat-${count.index + 1}"
  }
}

#setting up route table for nat instances
resource "aws_route_table" "nat_route_table" {
  vpc_id = aws_vpc.vpc_demo.id
  count  = length(var.public_subnets_cidr)
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.nat_gateway[*].id, count.index)
  }
  tags = {

    Name = "nat-route-table-${count.index + 1}"
  }
}

#associating private subnet to main (nat) route table
resource "aws_route_table_association" "nat_private_association" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(aws_route_table.nat_route_table[*].id, count.index)
}