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
│   ├── ovh-vps.yaml       # fail2ban + oha + towonel-hub (what `just ansible deploy-ovh-vps` runs)
│   └── proxmox-01.yaml    # fail2ban + proxmox (what `just ansible deploy-proxmox-01` runs)
└── roles/
    ├── network/           # VLAN sub-interfaces as NetworkManager connections
    ├── nut/               # Network UPS Tools (netserver mode)
    ├── fail2ban/          # SSH brute-force jail
    ├── oha/               # oha HTTP load-testing CLI (pinned GitHub release binary)
    ├── towonel-hub/       # towonel tunnel hub (systemd-managed docker run)
    └── proxmox/           # Proxmox VE repo config (no-subscription, no enterprise)
```

## Usage

```sh
just ansible deps        # install collections (first time)
just ansible ping        # SSH reachability (nut)
just ansible check       # dry-run + diff (network + nut)
just ansible deploy      # apply (network + nut)
just ansible deploy-nut  # apply only the NUT role

just ansible ping-ovh-vps    # SSH reachability (ovh-vps)
just ansible check-ovh-vps   # dry-run + diff (fail2ban + oha + towonel-hub)
just ansible deploy-ovh-vps  # apply (fail2ban + oha + towonel-hub)

just ansible ping-proxmox-01    # SSH reachability (proxmox-01)
just ansible check-proxmox-01   # dry-run + diff (fail2ban + proxmox repo config)
just ansible deploy-proxmox-01  # apply (fail2ban + proxmox repo config)
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
- **`towonel-hub`** — runs the [towonel](https://codeberg.org/towonel/towonel) tunnel hub (a
  self-hosted alternative to `cloudflared`) as a systemd-managed `docker run` (no Docker Compose,
  no `community.docker` — the module needs a Docker SDK that isn't installed on this host, so the
  role wraps the CLI directly in a unit). See the runbook below.

### Deploy

```sh
just ansible check-ovh-vps && just ansible deploy-ovh-vps
```

### Verify on the node

```sh
systemctl status fail2ban
sudo fail2ban-client status sshd
oha --version
systemctl status towonel-hub
docker logs -f towonel
```

## `towonel-hub` runbook

The hub is one half of the towonel tunnel (see GitHub issue
[swibrow/home-ops#1325](https://github.com/swibrow/home-ops/issues/1325)): it runs on this VPS
(`tunnel.wibrow.dev`) and an agent in the `pitower` cluster
(`kubernetes/apps/pitower/networking/towonel-agent/`) dials out to it, publishing `*.wibrow.dev`
routes. Since 2026-07-21 this is the **primary path** for `external.wibrow.dev` / `*.wibrow.dev`
(DNS CNAMEs to `tunnel.wibrow.dev`, non-proxied) — `cloudflared` still runs alongside it but only
owns the bare `wibrow.dev` apex (see `kubernetes/apps/pitower/networking/cloudflared/`).

The image (`towonel-hub-caddy`, not the plain `towonel-node`) runs two processes on this host:
Caddy, fronting the privileged ports, and the towonel binary itself, doing the actual work — the
**edge** (SNI passthrough for tenant traffic) and, embedded in the same binary, the **hub** control
API (agent bootstrap/registration). Caddy is there specifically to solve the ACME chicken-and-egg
bug described below — see that section for why.

### Key material — never regenerate

`roles/towonel-hub/vars/secrets.sops.yaml` holds `node.key`, `hub_kek.key`, `invite_hash.key`, and
`operator.key`, base64-encoded and SOPS-encrypted. These identify the hub's tenant and back every
invite ever issued — regenerating them breaks the agent's existing invite token and any others in
circulation. The role's copy task uses `force: false`, so it only *seeds* a missing volume (e.g. a
rebuilt VPS); it never overwrites keys already on disk. A second, independent backup lives at
`infra/towonel-hub/keys-backup.tar.gz.age` (age-encrypted, not SOPS) — keep both in sync if the keys
ever change.

### Config

- `TOWONEL_HUB_PUBLIC_URL` (`roles/towonel-hub/defaults/main.yaml: towonel_hub_public_url`) — the
  base URL embedded in every invite token. Confirmed from the agent's actual source
  (`crates/towonel-agent/src/stateless.rs`): every hub API call is
  `format!("{}/v1/...", token.hub_url.trim_end_matches('/'))` — there is **no automatic port
  inference**. Since the Caddy fix below, this is plain `https://tunnel.wibrow.dev` (no port) —
  see "The ACME chicken-and-egg bug" for why it used to need `:8443` and no longer does.
- `TOWONEL_HUB_ACME_EMAIL` (role var, → Caddyfile `email` directive) — Let's Encrypt registration
  email for **Caddy's own** automatic HTTPS cert on `towonel_hub_domain`. This is a real,
  publicly-trusted cert, not self-signed — the agent validates it with standard webpki roots and
  does not pin via the invite token. towonel's own ACME (`TOWONEL_HUB_TLS_*`) is unused now; the
  hub runs with no TLS config of its own and speaks plain HTTP on a loopback port.

### The ACME chicken-and-egg bug (confirmed in source, not just observed) — fixed via Caddy L4 SNI routing

Issuance uses TLS-ALPN-01 only (hardcoded upstream, no DNS-01, no static-cert file), and TLS-ALPN-01
validation always connects to port 443 — never a custom port. Read straight from
`crates/towonel-node/src/lib.rs`'s `run_node()`: in combined mode (hub+edge on one host, our setup)
`hub.run()` and `edge.run()` are **two fully independent tasks**, linked only by an in-process route
channel for tenant hostnames. The hub's ACME manager (`hub/acme.rs`) builds a correctly-wired
`CertResolver` + `EdgeAlpnSolver` (ALPN `acme-tls/1` support) — but previously it was wired only into
the hub's own `axum_server` listener on `TOWONEL_HUB_LISTEN_ADDR` (`:8443`), never into the edge's
`:443` listener. Since Let's Encrypt's TLS-ALPN-01 validator only ever dials port 443, and port 443
was exclusively the edge's (zero ACME awareness), **the hub's own cert could never be issued while
both ran combined on one host** — confirmed identical on `towonel-node:1.0.1` and `1.2.0`, and
reproduced with a direct external TLS probe (`openssl s_client -alpn acme-tls/1`) timed against a
live ACME challenge window: every connection reset, in-window or not. This was an upstream bug, not
a config mistake, and the old fix was a manual re-bootstrap dance repeated every ~60-90 days (see
git history on this file if you need the old workaround).

**The real fix: stop using towonel's own ACME for the hub, and put a tiny SNI router in front of
`:443`.** The image is `towonel-hub-caddy` (bundles the `towonel` binary with Caddy + the
`caddy-l4` plugin — upstream's own supported "reverse proxy multiplexing 443" pattern, though their
bundled Caddyfile only handles the edge side). `roles/towonel-hub/templates/Caddyfile.j2` adds a
second route:

- `layer4` listens on the public `:443` and peeks the TLS ClientHello SNI (no decryption, so this
  works for *any* connection including the ACME validator's, which presents
  `SNI=tunnel.wibrow.dev` same as a real client would):
  - `SNI == tunnel.wibrow.dev` → forwarded to Caddy's own loopback TLS listener
    (`towonel_hub_caddy_tls_port`). This is what makes ACME issuance possible at all now: the
    validator's connection lands on a listener that actually understands ACME, instead of the
    edge's dumb passthrough.
  - everything else (tenant hostnames) → forwarded to the edge's loopback listener
    (`127.0.0.1:4443`, image default) with PROXY v2, unchanged from upstream's default behavior.
- Caddy terminates real TLS for `tunnel.wibrow.dev` there using its own mature, independent
  automatic-HTTPS implementation (not towonel's `certon`-based one) and reverse-proxies plaintext
  HTTP to the hub's actual listener (`TOWONEL_HUB_LISTEN_ADDR=127.0.0.1:{{ towonel_hub_internal_port
  }}`, no TLS config on the towonel side at all — `build_hub_tls()` returns `None` and it just
  serves HTTP, which is what the image's own baked-in healthcheck already assumes).
- `disable_http_challenge` on Caddy's issuer because `:80` isn't published — the L4 router above
  already delivers everything TLS-ALPN-01 needs.

Net effect: no more manual renewal dance, `:8443` is no longer published at all (smaller attack
surface too), and the hub's `TOWONEL_HUB_PUBLIC_URL` is a normal port-443 HTTPS URL exactly like
upstream's own quick-start example assumes.

### Reissuing the invite token

Because the invite token embeds `TOWONEL_HUB_PUBLIC_URL`, changing that value (as this fix did —
dropping `:8443`) means the *existing* token the agent uses is stale and must be reissued from the
hub, then updated in Infisical at `/networking/towonel-agent/TOWONEL_INVITE_TOKEN`, then the agent
pod restarted. Confirm the hub's own cert is actually issuing successfully first (`curl -v
https://tunnel.wibrow.dev/v1/health` from off-VPS) — reissuing against a hub that still can't
present a valid cert just reproduces the same failure differently. Each invite is a new tenant
identity (`towonel invite create` doesn't reissue in place), so the old tenant is orphaned once the
agent switches — clean it up with `towonel tenant remove` once the new one is confirmed working.

### Verify

```sh
systemctl status towonel-hub
docker logs -f towonel                                    # caddy ACME issuance / bootstrap attempts
docker exec towonel curl -fsS http://127.0.0.1:8443/v1/health   # hub, plain HTTP inside the netns
curl -v https://tunnel.wibrow.dev/v1/health                     # from off-VPS: Caddy's real cert + SNI routing
kubectl --context=admin@pitower -n networking logs -l app.kubernetes.io/instance=towonel-agent
```

## `proxmox-01` node runbook

New Proxmox VE hypervisor host, VLAN 20 only, DHCP-assigned address (`proxmox-01.servers.local` —
set a UniFi DHCP reservation to pin it). Root SSH only (Proxmox ships no non-root sudo user); add
your pubkey to root's `authorized_keys` before the first run. Managed roles:

- **`fail2ban`** — same SSH brute-force jail as `ovh-vps`.
- **`proxmox`** — disables the enterprise repo (needs a paid subscription) and enables the
  `pve-no-subscription` repo so `apt` keeps working without one.

### Deploy

```sh
just ansible check-proxmox-01 && just ansible deploy-proxmox-01
```

This only covers host-level package repos. VM lifecycle (the Talos worker VM) is managed by
Terraform — see `terraform/proxmox/`.

### Network migration to VLAN20

`proxmox-01` currently sits on the default/native VLAN (`192.168.0.0/24`, untagged). To move it
onto VLAN20 (the pitower network, trunked/tagged on the switch port `nic1` connects to):

```sh
just ansible apply-network-proxmox-01
```

This tags `nic1` with VLAN20 (`nic1.20` → `vmbr0`, DHCP). Since the change reconfigures the exact
interface the SSH session is running over, the `ifreload -a` task losing its connection
("unreachable"/"connection lost") is **expected**, not a failure signal.

**No automatic rollback** - the template task keeps a timestamped backup of the previous
`/etc/network/interfaces` next to it (Ansible's `backup: true`), but nothing restores it
automatically. After applying, find the new address (UniFi client list or DHCP leases for MAC
`f8:bc:12:1d:46:30`) and confirm SSH works there. If it's broken, fix it manually via the iDRAC
console: `cp /etc/network/interfaces.<timestamp>~ /etc/network/interfaces && ifreload -a`.

Once confirmed, update `ansible/inventory/hosts.yaml`'s `proxmox-01` entry and `mise.toml`'s
`PROXMOX_VE_ENDPOINT` to the new address, and consider a DHCP reservation to keep it stable.

## Secrets

```sh
sops roles/nut/vars/secrets.sops.yaml          # edit
sops -d roles/nut/vars/secrets.sops.yaml       # view
```
