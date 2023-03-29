terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.0"
    }
  }
}


provider "aws" {
  region                   = var.region
  shared_credentials_files = [pathexpand("~/.aws/credentials")]
  shared_config_files      = [pathexpand("~/.aws/config")]
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

resource "aws_key_pair" "ec2-kp" {
  key_name   = "deploy-key"
  public_key = file(join("", [pathexpand("~/.ssh/${var.deploy_key}"), ".pub"]))
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

  dynamic "ingress" {
    for_each = var.open_ports

    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Open TCP port ${ingress.value}"
    }
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "all"
  }
}
resource "aws_instance" "web" {
  # ami                         = data.aws_ami.ubuntu.id
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sec_group.id]
  # security_groups             = [aws_security_group.sec_group.id]

  key_name = aws_key_pair.ec2-kp.key_name

  connection {
    host        = self.public_ip
    user        = "ubuntu"
    type        = "ssh"
    private_key = file(pathexpand("~/.ssh/${var.deploy_key}"))
  }

  provisioner "file" {
    source      = pathexpand("~/.ssh/${var.deploy_key}")
    destination = "/home/ubuntu/.ssh/${var.deploy_key}"
  }

  provisioner "remote-exec" {
    script = "install-docker.sh"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

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
