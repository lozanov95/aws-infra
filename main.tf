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

  ingress {
    cidr_blocks = ["${var.my_ip}/32"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "Opened SSH port to the managing PC"
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "all"
  }
}

resource "aws_iam_instance_profile" "prof" {
  role = aws_iam_role.cloudwatch_agent_role.name
}

resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sec_group.id]

  key_name             = aws_key_pair.ec2-kp.key_name
  iam_instance_profile = aws_iam_instance_profile.prof.name

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

  provisioner "file" {
    source      = "amazon-cloudwatch-agent.json"
    destination = "/home/ubuntu/amazon-cloudwatch-agent.json"
  }

  provisioner "remote-exec" {
    script = "install-docker.sh"
  }

  provisioner "remote-exec" {
    script = "install-cloudwatch.sh"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "INFRA server"
  }
}

data "aws_iam_policy" "cw_server_policy" {
  name = "CloudWatchAgentServerPolicy"
}

data "aws_iam_policy" "ssm_role" {
  name = "AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_iam_role" "cloudwatch_agent_role" {
  name = "cloudwatch_agent_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = [data.aws_iam_policy.cw_server_policy.arn, data.aws_iam_policy.ssm_role.arn]
}

resource "aws_ssm_document" "docker_prune" {
  name          = "DockerSystemPrune"
  document_type = "Command"
  target_type   = "/AWS::EC2::Instance"
  content       = <<DOC
  {
    "schemaVersion": "1.2",
    "description": "Clear the docker unused files.",
    "parameters": {},
    "runtimeConfig": {
      "aws:runShellScript": {
        "properties": [
          {
            "id": "0.aws:runShellScript",
            "runCommand": ["docker system prune -f"]
          }
        ]
      }
    }
  }
DOC
}

resource "aws_ssm_document" "make_prod" {
  name          = "MaimundaMakeProd"
  document_type = "Command"
  target_type   = "/AWS::EC2::Instance"
  content       = <<DOC
  {
    "schemaVersion": "1.2",
    "description": "Recreate the maimunda docker image and rerun the container.",
    "parameters": {},
    "runtimeConfig": {
      "aws:runShellScript": {
        "properties": [
          {
            "id": "0.aws:runShellScript",
            "runCommand": ["cd /home/ubuntu/zamunda-scrapper && sudo -u ubuntu make prod"]
          }
        ]
      }
    }
  }
DOC
}

resource "aws_cloudwatch_event_rule" "my_event_rule" {
  name        = "LowDiskRule"
  description = "LowDiskRule"

  event_pattern = <<EOF
    {
      "source": [
        "aws.cloudwatch"
      ],
      "detail-type": [
        "CloudWatch Alarm State Change"
      ],
      "detail": {
        "alarmName": [
          "low diskspace"
        ]
      }
    }
  EOF
}

resource "aws_cloudwatch_event_target" "my_event_target" {
  rule = aws_cloudwatch_event_rule.my_event_rule.name

  run_command_targets {
    key    = "InstanceIds"
    values = [aws_instance.web.id]
  }
  arn      = aws_ssm_document.docker_prune.arn
  role_arn = aws_iam_role.ssm_lifecycle.arn
}

data "aws_iam_policy_document" "ssm_lifecycle_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ssm_lifecycle" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = [aws_instance.web.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = [aws_ssm_document.docker_prune.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = [aws_ssm_document.make_prod.arn]
  }
}

resource "aws_iam_role" "ssm_lifecycle" {
  name               = "SSMLifecycle"
  assume_role_policy = data.aws_iam_policy_document.ssm_lifecycle_trust.json
}

resource "aws_iam_policy" "ssm_lifecycle" {
  name   = "SSMLifecycle"
  policy = data.aws_iam_policy_document.ssm_lifecycle.json
}

resource "aws_iam_role_policy_attachment" "ssm_lifecycle" {
  policy_arn = aws_iam_policy.ssm_lifecycle.arn
  role       = aws_iam_role.ssm_lifecycle.name
}

resource "aws_cloudwatch_metric_alarm" "diskspace" {
  alarm_name          = "low diskspace"
  metric_name         = "disk_used_percent"
  comparison_operator = "GreaterThanThreshold"
  namespace           = "CWAgent"
  evaluation_periods  = 2
  period              = 360
  threshold           = "85"
  datapoints_to_alarm = 2
  statistic           = "Average"

  dimensions = {
    InstanceId = aws_instance.web.id
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]
}

resource "aws_iam_role" "gh_role" {
  name = "github_deploy_role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${split(":", aws_iam_policy.ssm_lifecycle.arn)[4]}:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity"
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
          "StringLike" : {
            "token.actions.githubusercontent.com:sub" : "repo:lozanov95/zamunda-scrapper:*",
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "deploy_role" {
  policy_arn = aws_iam_policy.ssm_lifecycle.arn
  role       = aws_iam_role.gh_role.name
}
