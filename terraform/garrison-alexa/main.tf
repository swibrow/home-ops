terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "swibrow-pitower-tf-state"
    key          = "garrison-alexa.tfstate"
    region       = "eu-central-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  name = "garrison-crier"

  tags = {
    Stack      = local.name
    GithubOrg  = "swibrow"
    GithubRepo = "home-ops"
  }
}

# Generated here rather than passed in, so CI applies need no secret input.
# Copy it into Infisical /garrison/CRIER_TOKEN:
#   terraform output -raw crier_token
resource "random_password" "crier_token" {
  length  = 48
  special = false
}
