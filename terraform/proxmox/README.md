# terraform/proxmox

Manages VM and LXC container lifecycle on the `proxmox-01` hypervisor via the
[`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider.
Host-level config (repos, fail2ban) is handled separately by Ansible - see `ansible/README.md`'s
`proxmox-01` runbook.

Scope boundary: this stack creates the VM shell (CPU/memory/disk/NIC) and attaches the Talos
installer ISO. It does **not** configure Talos itself - the VM boots into Talos maintenance mode,
and from there it's `talosctl apply-config` + a `talos/pitower/node/<host>/` topf layer, same as
the bare-metal workers.

## Garage S3 (`ct_garage.tf`)

An LXC container, not a VM: Garage is a single static binary with no kernel requirements, so a VM
would only add a guest kernel and a virtual disk layer between it and the ZFS pool. The 500G data
volume is a mount point at `/var/lib/garage` (a plain ZFS dataset), separate from the 16G rootfs -
the container can be rebuilt without touching data, and the dataset snapshots/replicates on its own.
Sizing lives in the `garage` variable.

Same scope boundary as the VMs: Terraform creates the container + data volume and injects your SSH
key; installing and configuring Garage is Ansible's job (`ansible/roles/garage`, run with
`just ansible deploy-garage`). Networking is DHCP on VLAN 20 (via
`vmbr0`, untagged from the guest's perspective) - pin the lease with a UniFi reservation using
`terraform output garage_mac_address`, same as `nut` and `proxmox-01`.

Before applying, verify `lxc_template_url` still resolves - Proxmox rolls the Debian template's
point release and drops old ones. Check with `pveam available --section system` on the host and bump
the variable if the exact filename has moved on.

This node is intended as one replica of a multi-node Garage layout; a second replica is planned on
the Synology NAS. Garage wants an odd number of nodes for quorum on metadata, so plan for a third
(or a lightweight tiebreaker) before relying on it for anything that can't be re-derived.

## Credentials

The provider reads `PROXMOX_VE_ENDPOINT` / `PROXMOX_VE_API_TOKEN` / `PROXMOX_VE_INSECURE` from the
environment (deliberately not set in `main.tf`, so the token never lives in a `.tf`/tfvars file).

`var.ssh_public_keys` (the keys injected into container root accounts) is likewise supplied from the
environment as `TF_VAR_ssh_public_keys`, age-encrypted in the root `mise.toml` alongside the API
token. It holds a **JSON list** because the variable is `list(string)` - Terraform parses
`TF_VAR_*` values for non-string types as HCL. Without it the `locals` block falls back to whichever
operator's `~/.ssh/id_ed25519.pub` runs the apply, which on the self-hosted runner means CI's key
rather than yours. Update it with:

```sh
mise set --age-encrypt --file mise.toml 'TF_VAR_ssh_public_keys=["ssh-ed25519 AAAA... you@host"]'
```

Note that `ct_garage.tf` ignores changes to `initialization[0].user_account`, so changing this var
does **not** re-key an already-created container - it only applies to one created from scratch. To
add a key to a running container, append it to `/root/.ssh/authorized_keys` via
`pct exec <vmid>` on the host.

These come from the repo root `mise.toml`'s `[env]` block: `PROXMOX_VE_ENDPOINT` and
`PROXMOX_VE_INSECURE` are plain, `PROXMOX_VE_API_TOKEN` is age-encrypted (same pattern as
`AGENTMEMORY_SECRET` - see `reference_mise_age_secrets`). mise injects `[env]` automatically via
its shell hook, so nothing extra needs sourcing before running `terraform` - just be in a mise-managed
shell in the repo. To rotate the token: `mise set PROXMOX_VE_API_TOKEN=<new-token> --encrypt` (or
edit `mise.toml` by hand with a freshly age-encrypted value).

## Usage

The S3 state backend (shared by every `terraform/*` stack, not just this one) needs AWS
credentials that `aws login --profile wibrow` alone doesn't provide - that populates a
`login_session`, which Terraform's AWS SDK can't consume directly. Use the `wibrow-tf` profile
instead (already in `~/.aws/config`, wraps `wibrow`'s session via `credential_process`):

```sh
AWS_PROFILE=wibrow-tf just tf::init-proxmox
AWS_PROFILE=wibrow-tf just tf::plan-proxmox
AWS_PROFILE=wibrow-tf just tf::apply-proxmox
```

## CI

`.github/workflows/terraform-proxmox.yaml` plans on PRs touching `terraform/proxmox/**` and
applies on merge to `main`. It is a separate workflow from `terraform-{plan,apply}.yaml` because
this stack must run on the self-hosted `home-ops` runner — the Proxmox API lives on VLAN 20 and a
GitHub-hosted runner cannot reach it. That means a PR-triggered workflow executing on the cluster
in a public repo, the same tradeoff `talos-diff.yaml` already makes for the same reason.

Credentials are not duplicated as repo secrets: the job installs mise, writes the
`AGE_SECRET_KEY` repo secret to `~/.config/mise/age.txt`, and reads `PROXMOX_VE_*` straight out of
the root `mise.toml` — so rotating the token with `mise set PROXMOX_VE_API_TOKEN --encrypt` updates
local and CI together. `MISE_AUTO_INSTALL=0` keeps `mise env` from installing the whole `[tools]`
block just to print `[env]`. State backend credentials still come from AWS OIDC, as with the other
stacks.

A preflight step probes `${PROXMOX_VE_ENDPOINT}/api2/json/version` before Terraform runs — a
failure there means the runner can't resolve `proxmox-01.servers.local` or route to VLAN 20, not
that the plan is broken.

## Before applying

The `terraform` API token (`root@pam!terraform`) needs `privsep 0` for `proxmox_download_file`'s
metadata lookup to work - Proxmox gates its URL-fetch API (`query-url-metadata`) behind
`Sys.Modify`/`Datastore.AllocateTemplate`, which a privilege-separated token doesn't inherit from
`root` automatically even though the underlying user has full rights. Already set
(`pveum user token modify root@pam terraform --privsep 0`); if you ever recreate the token, either
pass `--privsep 0` at creation or re-run that command, or the ISO download will 401.

`disk_storage` defaults to `local-zfs` - the ZFS RAID10 pool (`rpool`, Disks → ZFS in the UI) that
holds VM disks on this host. `iso_storage` defaults to `local` (the directory storage Proxmox also
carves out of `rpool` for ISOs/templates). Confirm both storage IDs with `pvesm status` on the host
before applying - `local-zfs` is the installer default but worth a sanity check.

Also worth checking `zpool list rpool` for actual usable capacity before sizing `talos_worker.disk`
(200GB default) - RAID10 (striped mirrors) gives you half the raw disk capacity, and ZFS itself
wants some free space headroom (avoid filling the pool past ~80%) for performance.

`talos_worker` sizing (cores/memory) also defaults to a guess - adjust to taste.

## After applying

`terraform output talos_worker_mac_address` gives the NIC MAC. Boot the VM, let it come up in
Talos maintenance mode, then add a node entry under `talos/pitower/node/` (mac-matched, like
`worker-04`'s) and run `topf apply`.
