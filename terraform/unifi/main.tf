terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket                  = "swibrow-pitower-tf-state"
    key                     = "unifi.tfstate"
    region                  = "eu-central-2"
    use_lockfile            = true
    encrypt                 = true
    skip_metadata_api_check = true
  }

  required_providers {
    unifi = {
      source  = "filipowm/unifi"
      version = "~> 1.1.0"
    }
  }
}

# Credentials come from UNIFI_API / UNIFI_API_KEY / UNIFI_INSECURE env vars
# (see terraform/unifi/README.md) - deliberately not set here so the API key
# never has to live in a .tf file or tfvars.
provider "unifi" {}
