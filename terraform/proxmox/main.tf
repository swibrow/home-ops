terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket                  = "swibrow-pitower-tf-state"
    key                     = "proxmox.tfstate"
    region                  = "eu-central-2"
    use_lockfile            = true
    encrypt                 = true
    skip_metadata_api_check = true
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# Credentials come from PROXMOX_VE_ENDPOINT / PROXMOX_VE_API_TOKEN / PROXMOX_VE_INSECURE
# env vars (see terraform/proxmox/README.md) - deliberately not set here so the API
# token never has to live in a .tf file or tfvars.
provider "proxmox" {}
