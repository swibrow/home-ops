# Ansible

Configuration management for **plain (non-Talos) Linux hosts**. Everything else in this repo is
Talos + Kubernetes; this tree exists for boxes that need a normal OS — e.g. the `nut` Raspberry Pi,
which needs direct USB access to the UPSes, and `ovh-vps`, a public OVH VPS outside the cluster.

Secrets are **SOPS-encrypted** with the repo age key (no Ansible Vault). The root `justfile`
exports `SOPS_AGE_KEY_FILE=age.key`; the `community.sops` collection decrypts `*.sops.yaml` at
play time.

## Layout

```
ansible/
├── ansible.cfg            # inventory path, sudo, community.sops vars plugin
├── requirements.yaml      # community.general + community.sops
├── inventory/hosts.yaml   # hosts (set ansible_host / ansible_user)
├── playbooks/
│   ├── site.yaml          # network + nut (what `just ansible deploy` runs)
│   ├── nut.yaml           # NUT role only
│   └── ovh-vps.yaml       # fail2ban + oha (what `just ansible deploy-ovh-vps` runs)
└── roles/
    ├── network/           # VLAN sub-interfaces as NetworkManager connections
    ├── nut/               # Network UPS Tools (netserver mode)
    ├── fail2ban/          # SSH brute-force jail
    └── oha/               # oha HTTP load-testing CLI (pinned GitHub release binary)
```

## Usage

```sh
just ansible deps        # install collections (first time)
just ansible ping        # SSH reachability (nut)
just ansible check       # dry-run + diff (network + nut)
just ansible deploy      # apply (network + nut)
just ansible deploy-nut  # apply only the NUT role

just ansible ping-ovh-vps    # SSH reachability (ovh-vps)
just ansible check-ovh-vps   # dry-run + diff (fail2ban + oha)
just ansible deploy-ovh-vps  # apply (fail2ban + oha)
```

## Networking (`network` role)

The node lives **only on VLAN 20**. It has a single NIC, so `eth0` stays link-up to carry the
tagged VLAN but holds **no IP on the untagged/native LAN** (`method4/6: disabled`, carrier only).
The tagged **VLAN 20** sub-interface (`vlan20`) owns the address and the default route — internet
egresses via the VLAN-20 gateway `10.20.0.1`.

NetworkManager is the source of truth on this host (netplan only renders to it), so interfaces are
managed as **NM connections via `community.general.nmcli`** — NOT netplan drop-in files. A netplan
`*.yaml` + `netplan apply` approach regenerates every connection and made `eth0` grab a second
DHCP lease, so it is deliberately avoided. The nmcli module updates the stored profile but does not
reactivate the live connection, so the role notifies handlers that bring the VLAN up (gaining the
default route) and then `nmcli device reapply eth0` (dropping its IP) — in that order, so a default
route always exists during the cutover.

VLAN 20 hands out a `/16` address, so the whole `10.20.0.0/16` is on-link — no extra route needed
to reach the other `/24` clusters.

### DNS / domains (UniFi, per-network)

| Network        | Domain          | nut name             |
|----------------|-----------------|----------------------|
| primary LAN    | `internal`      | `nut` (mDNS/host)    |
| servers VLAN 20| `servers.local` | `nut.servers.local`  |

`nut.servers.local` auto-registers from the VLAN-20 DHCP lease and resolves on networks that
use the VLAN-20 DNS (`10.20.0.1`). Hosts on other VLANs (e.g. Home Assistant on the IoT net,
whose search domain is `iot`) can't resolve bare `nut` — use the FQDN `nut.servers.local`, or
add a UniFi static DNS record / DHCP reservation if cross-VLAN DNS is blocked. Both LAN IPs are
DHCP and can change — prefer names or a reservation over hardcoding an address.

## `nut` node runbook

The node runs NUT in **netserver** mode and serves two UPSes on tcp/3493:
`eaton` (Eaton 5S, `usbhid-ups`, vendorid `0463`) and `cyberpower` (CyberPower
PR1500LCDRT2U, `usbhid-ups`, vendorid `0764`).

### 1. Before the first real deploy: identify the USB devices

Two USB UPSes make `port = auto` ambiguous. On the node:

```sh
sudo nut-scanner -U
```

Copy each device's `vendorid` and/or `serial` into `roles/nut/defaults/main.yaml`
(`nut_devices[*].vendorid` / `serial`) so each driver binds the right UPS, and confirm the driver
from the scan output. (A UPS plugged in *before* NUT was installed keeps `root:root` on its USB
node — the role's udev-reload handler fixes this; on a clean install order it's automatic.)

### 2. Deploy

```sh
just ansible check && just ansible deploy
```

### 3. Verify on the node

```sh
upsc eaton            # battery.charge, ups.status, battery.runtime
upsc cyberpower
systemctl status nut-server nut-monitor
```

From another LAN host: `upsc eaton@<nut-ip>` (confirms netserver + firewall).

### 4. Home Assistant

HA's NUT integration is added via the UI (config entry, not YAML):
Settings → Devices & Services → **Add Integration → Network UPS Tools (NUT)** →
host = `nut.servers.local` (or the node IP), port 3493, username `monitor`, password from
`roles/nut/vars/secrets.sops.yaml` (`sops -d` to read it). HA detects both UPS aliases.
HA is on the IoT network and can't resolve bare `nut`; use the `nut.servers.local` FQDN or a
UniFi DHCP reservation — see the DNS note above.

## `ovh-vps` node runbook

Public OVH VPS (Debian 13/trixie), not part of the pitower cluster. SSH is key-only
(`PasswordAuthentication no`); the `debian` user has passwordless sudo. Its public IP (and rDNS,
which resolves straight back to it) is SOPS-encrypted as `ansible_host` in
`inventory/host_vars/ovh-vps.sops.yaml` (auto-decrypted at inventory-load time by the
`community.sops` vars plugin — nothing that reveals the IP lives in plaintext git history);
`sops -d inventory/host_vars/ovh-vps.sops.yaml` to view it. Managed roles so far:

- **`fail2ban`** — jails `/etc/fail2ban/jail.local` from `roles/fail2ban/defaults/main.yaml`
  (`fail2ban_jails`); ships with an `sshd` jail only.
- **`oha`** — installs the [oha](https://github.com/hatoo/oha) HTTP load-testing CLI to
  `/usr/local/bin/oha` from a pinned, checksum-verified GitHub release binary (no Debian package
  exists). Bump `oha_version` and both arch checksums in `roles/oha/defaults/main.yaml` together —
  GitHub doesn't publish a checksums file for oha releases, so checksums are captured by hand from
  the release assets.

### Deploy

```sh
just ansible check-ovh-vps && just ansible deploy-ovh-vps
```

### Verify on the node

```sh
systemctl status fail2ban
sudo fail2ban-client status sshd
oha --version
```

## Secrets

```sh
sops roles/nut/vars/secrets.sops.yaml          # edit
sops -d roles/nut/vars/secrets.sops.yaml       # view
```
