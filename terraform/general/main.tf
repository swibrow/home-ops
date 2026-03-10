terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket                  = "swibrow-pitower-tf-state"
    key                     = "general.tfstate"
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
  }
}

provider "aws" {
  region = "eu-central-2"
}

locals {
  name = "pitower"

  tags = {
    Stack      = local.name
    GithubOrg  = "swibrow"
    GithubRepo = "home-ops"
  }
}
