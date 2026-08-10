# terraform/unifi

Manages the UniFi Cloud Gateway (Network app) config via the
[`filipowm/unifi`](https://registry.terraform.io/providers/filipowm/unifi/latest/docs) provider - a
maintained fork of the archived `paultyng/terraform-provider-unifi`. It talks to the controller's
local API, so this stack can only run from something on the LAN, same constraint as
`terraform/proxmox`.

## Scope

The five corporate networks (`networks.tf`) and the cluster-node DHCP reservations
(`reservations.tf`, `unifi_user` resources), the latter replacing the manual "set a UniFi
reservation" steps that `ansible/README.md` and `ansible/inventory/hosts.yaml` point at. The
provider also supports firewall rules/groups, port forwards, DNS records, and WLANs - add `.tf`
files for those as they're needed rather than scaffolding unused resources now.

Everything here already existed on the controller and was adopted, not created - see
[Adopting existing config](#adopting-existing-config).

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

## Adopting existing config

Every resource in this stack predates it, so nothing here should ever be *created* on a first
apply - it has to be imported. `imports.tf` holds an `import` block per resource, keyed on the
controller's Mongo ObjectID, which makes the adopting run part of the normal plan/apply rather
than a pile of out-of-band `terraform import` commands.

This is not theoretical: the first apply ran without them and tried to create all five networks.
The controller rejected every one (`api.err.VlanUsed`, and `api.err.PdRequiresAssignedDhcpv6Wan`
on `Default`), so nothing was duplicated and the reservations never ran - they depend on
`unifi_network.servers.id`. Do not rely on that rejection as a safety net.

To collect the IDs for a new resource, query the controller's REST API directly:

```sh
eval "$(mise env -s bash)"
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" "$UNIFI_API/proxy/network/api/s/default/rest/networkconf" \
  | jq -r '.data[] | [._id, .name, (.vlan//"-"), (.ip_subnet//"-")] | @tsv'
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" "$UNIFI_API/proxy/network/api/s/default/rest/user" \
  | jq -r '.data[] | select(.use_fixedip) | [._id, .mac, (.name//""), .fixed_ip] | @tsv'
```

(The reservation flag is `use_fixedip`, one `i` - `use_fixeddip` silently matches nothing.)

The import blocks are kept after the adopting apply. They are no-ops once the resources are in
state, and if the state object is ever lost they make the rebuild re-adopt rather than re-attempt
creates.

### Verifying before you merge

The apply runs on merge to `main`, so validate the plan first. To do that without AWS state
credentials, copy the stack to a scratch dir, swap `backend "s3"` for `backend "local" {}`, and
plan there - it is read-only against the controller:

```sh
cp terraform/unifi/*.tf /tmp/unifi-check/    # then edit the backend block
eval "$(mise env -s bash)"
terraform -chdir=/tmp/unifi-check init && terraform -chdir=/tmp/unifi-check plan
```

A correct adopting plan is `16 to import, 0 to add, 11 to change, 0 to destroy` - the 11 being
`name` / `network_id` / the two provider-side flags on the reservations. **Any "to add" on a
`unifi_network` means an import block is missing or has the wrong ID.** Note that `terraform` on
PATH may be the 1.6.6 in `~/bin`, which is below this stack's `required_version` and has no
`for_each` in import blocks; use the mise 1.15.8 binary.

### IPv6 defaults

`networks.tf` pins `ipv6_ra_*` / `dhcp_v6_*` to the values the controller actually stores (0 /
`false`). The provider schema defaults them to RFC lifetimes (86400/14400) and
`dhcp_v6_dns_auto = true`, so leaving them unset makes adoption write those defaults back. That is
inert on the four networks with `ipv6_interface_type = "none"`, but `Default` carries the ISP
prefix delegation, where the same drift also flipped `ipv6_ra_enable` `true -> null` - dropping
router advertisements on the main LAN. Pinning them keeps the network side of the plan a true
no-op.

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
