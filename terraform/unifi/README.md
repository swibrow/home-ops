# terraform/unifi

Manages the UniFi Cloud Gateway (Network app) config via the
[`filipowm/unifi`](https://registry.terraform.io/providers/filipowm/unifi/latest/docs) provider - a
maintained fork of the archived `paultyng/terraform-provider-unifi`. It talks to the controller's
local API, so this stack can only run from something on the LAN, same constraint as
`terraform/proxmox`.

## Scope

Currently just DHCP reservations (`reservations.tf`, `unifi_user` resources), replacing the manual
"set a UniFi reservation" steps that `ansible/README.md` and `ansible/inventory/hosts.yaml`
currently point at. The provider also supports networks/VLANs, firewall rules/groups, port
forwards, DNS records, and WLANs - add `.tf` files for those as they're needed rather than
scaffolding unused resources now.

## Credentials

The provider reads `UNIFI_API` (controller base URL, e.g. `https://10.20.0.1`, no `/api` suffix),
`UNIFI_API_KEY`, and `UNIFI_INSECURE` (`true` if the gateway's cert is self-signed) from the
environment - same pattern as `terraform/proxmox`'s `PROXMOX_VE_*` vars, deliberately not set in
`main.tf` so the key never lives in a `.tf`/tfvars file.

Generate the key from the controller UI: **Settings → Control Plane → Admins & Users → your admin
user → Create API Key**. Requires controller version 9.0.108+; use `UNIFI_USERNAME`/`UNIFI_PASSWORD`
instead on older firmware. Create a dedicated Terraform admin with a **Limited Admin, Local Access
Only** role rather than reusing your own account.

Add these to the root `mise.toml`'s `[env]` block, age-encrypted like `PROXMOX_VE_API_TOKEN`:

```sh
mise set --age-encrypt --file mise.toml UNIFI_API=https://10.20.0.1
mise set --age-encrypt --file mise.toml UNIFI_API_KEY=<key>
mise set --age-encrypt --file mise.toml UNIFI_INSECURE=true
```

Confirm `UNIFI_API` against the gateway's actual LAN management address before the first apply -
it isn't recorded elsewhere in this repo.

## Adding a reservation

```hcl
reservations = {
  proxmox-01 = {
    mac      = "f8:bc:12:1d:46:30" # from ansible/README.md's proxmox-01 runbook
    fixed_ip = "10.20.0.X"         # pick a free VLAN-20 address
  }
}
```

For `garage-01`, pull the MAC from the `terraform/proxmox` state instead of copying it by hand:

```hcl
data "terraform_remote_state" "proxmox" {
  backend = "s3"
  config = {
    bucket = "swibrow-pitower-tf-state"
    key    = "proxmox.tfstate"
    region = "eu-central-2"
  }
}

# reservations.garage-01.mac = data.terraform_remote_state.proxmox.outputs.garage_mac_address
```

`nut-01`'s MAC isn't recorded anywhere in this repo yet - pull it from the UniFi client list
(`Insights → Client Devices`) before adding it here.

## Usage

```sh
AWS_PROFILE=wibrow-tf just tf::init-unifi
AWS_PROFILE=wibrow-tf just tf::plan-unifi
AWS_PROFILE=wibrow-tf just tf::apply-unifi
```

## CI

`.github/workflows/terraform-unifi.yaml` plans on PRs touching `terraform/unifi/**` and applies on
merge to `main` - same shape as `terraform-proxmox.yaml`, on the self-hosted `home-ops` runner,
since a GitHub-hosted runner cannot reach the gateway's LAN-only API.
