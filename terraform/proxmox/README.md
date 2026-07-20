# terraform/proxmox

Manages VM lifecycle on the `proxmox-01` hypervisor via the
[`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider.
Host-level config (repos, fail2ban) is handled separately by Ansible - see `ansible/README.md`'s
`proxmox-01` runbook.

Scope boundary: this stack creates the VM shell (CPU/memory/disk/NIC) and attaches the Talos
installer ISO. It does **not** configure Talos itself - the VM boots into Talos maintenance mode,
and from there it's `talosctl apply-config` + a `talos/pitower/node/<host>/` topf layer, same as
the bare-metal workers.

## Credentials

The provider reads `PROXMOX_VE_ENDPOINT` / `PROXMOX_VE_API_TOKEN` / `PROXMOX_VE_INSECURE` from the
environment (deliberately not set in `main.tf`, so the token never lives in a `.tf`/tfvars file).

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
