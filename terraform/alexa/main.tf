terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "swibrow-pitower-tf-state"
    key          = "alexa.tfstate"
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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  name = "pitower-alexa"

  tags = {
    Stack      = local.name
    GithubOrg  = "swibrow"
    GithubRepo = "home-ops"
  }
}
