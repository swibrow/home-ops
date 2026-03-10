terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket                  = "swibrow-pitower-tf-state"
    key                     = "bootstrap.tfstate"
    region                  = "eu-central-2"
    use_lockfile            = true
    encrypt                 = true
    skip_metadata_api_check = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "6.4.0"

  tags = local.tags
}

################################################################################
# GitHub OIDC Role
################################################################################

module "iam_github_oidc_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.4.0"

  name            = "${local.name}-oidc"
  use_name_prefix = false

  enable_github_oidc = true
  oidc_subjects      = var.subjects

  policies = {
    additional = aws_iam_policy.additional.arn
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
