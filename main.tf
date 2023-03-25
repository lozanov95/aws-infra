provider "aws" {
  region                   = var.region
  shared_credentials_files = ["C:/Users/lozanov/.aws/credentials"]
  shared_config_files      = ["C:/Users/lozanov/.aws/config"]
}

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
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "VPC"
  }
}
resource "aws_subnet" "subnet" {
  cidr_block = "10.0.0.0/24"
  vpc_id     = aws_vpc.vpc.id

  tags = {
    Name = "subnet"
  }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw"
  }
}
resource "aws_route_table" "name" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table_association" "name" {
  route_table_id = aws_route_table.name.id
  subnet_id      = aws_subnet.subnet.id

}
resource "aws_security_group" "sec_group" {
  vpc_id = aws_vpc.vpc.id
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 65000
    protocol    = "all"
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 65000
    protocol    = "all"
  }
}
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sec_group.id]


  tags = {
    Name = "INFRA server"
  }
}
output "aws_instance_ip" {
  depends_on = [
    aws_instance.web
  ]
  value       = aws_instance.web.public_ip
  description = "EC2's ip"
}
