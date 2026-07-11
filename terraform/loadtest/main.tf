###############################################################################
# Throwaway load-test stack: a single Graviton EC2 load generator (k6),
# driven over SSM (no SSH / no inbound). Self-contained VPC for easy destroy.
#   terraform -chdir=terraform/loadtest apply
#   ... run k6 via SSM ...
#   terraform -chdir=terraform/loadtest destroy
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-central-2" # Zurich
}

variable "instance_type" {
  type    = string
  default = "c7g.large" # 2 vCPU Graviton3, plenty to saturate a home uplink
}

provider "aws" {
  region = var.region
  # Credentials come from the environment (exported from the `wibrow` profile);
  # see the apply wrapper. Avoids profile-resolution issues with temp creds.
  default_tags {
    tags = {
      Project   = "home-ops-loadtest"
      Ephemeral = "true"
      ManagedBy = "terraform"
    }
  }
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# --- Minimal network -------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = "10.99.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "loadtest" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "loadtest" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.99.1.0/24"
  availability_zone       = "eu-central-2b" # c7g.large not offered in -2a
  map_public_ip_on_launch = true
  tags                    = { Name = "loadtest-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "loadtest-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Egress-only: SSM + the load test. No inbound.
resource "aws_security_group" "this" {
  name        = "loadtest"
  description = "loadtest egress only"
  vpc_id      = aws_vpc.this.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "loadtest" }
}

# --- SSM instance role (no SSH key needed) ---------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "loadtest-ssm"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "loadtest-ssm"
  role = aws_iam_role.this.name
}

# --- Load generator --------------------------------------------------------
resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    LATEST=$(curl -s https://api.github.com/repos/grafana/k6/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -sSL "https://github.com/grafana/k6/releases/download/$${LATEST}/k6-$${LATEST}-linux-arm64.tar.gz" -o /tmp/k6.tgz
    tar -xzf /tmp/k6.tgz -C /tmp
    install -m755 /tmp/k6-$${LATEST}-linux-arm64/k6 /usr/local/bin/k6
    k6 version > /var/log/k6-install.log 2>&1
  EOF

  tags = { Name = "loadtest-k6" }
}

output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  value = aws_instance.this.public_ip
}
