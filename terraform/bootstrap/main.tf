terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "swibrow-pitower-tf-state"
    key          = "bootstrap.tfstate"
    region       = "eu-central-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = local.region
}

locals {
  name   = "pitower"
  region = "eu-central-2"

  tags = merge(var.tags, {
    Stack       = local.name
    StateBucket = resource.aws_s3_bucket.state.id
  })
}

################################################################################
# GitHub OIDC Provider
# Note: This is one per AWS account
################################################################################

module "iam_github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-provider"
  version = "5.58.0"

  tags = local.tags
}

################################################################################
# GitHub OIDC Role
################################################################################

module "iam_github_oidc_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version = "5.58.0"

  name = "${local.name}-oidc"

  subjects = var.subjects

  policies = {
    additional = aws_iam_policy.additional.arn
    # ManagedPolicy = "arn:aws:iam::aws:policy/ManagedPolicyName"
  }

  tags = local.tags
}

resource "aws_iam_policy" "additional" {
  name        = "${local.name}-additional"
  description = "God Mode Policy for the pitower GitHub OIDC Role, this is bad!"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = local.tags
}
