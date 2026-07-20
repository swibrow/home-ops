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
│   └── ovh-vps.yaml       # fail2ban + oha + towonel-hub (what `just ansible deploy-ovh-vps` runs)
└── roles/
    ├── network/           # VLAN sub-interfaces as NetworkManager connections
    ├── nut/               # Network UPS Tools (netserver mode)
    ├── fail2ban/          # SSH brute-force jail
    ├── oha/               # oha HTTP load-testing CLI (pinned GitHub release binary)
    └── towonel-hub/       # towonel tunnel hub (systemd-managed docker run)
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
routes. The image shares one process for two roles on port 443 — the **edge** (SNI passthrough for
tenant traffic) and, embedded in the same binary, the **hub** control API on `:8443` (agent
bootstrap/registration).

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
  inference**. Upstream's docs example omits the port (`https://hub.example.eu`), but that only
  works behind a reverse proxy that multiplexes port 443 by path/protocol (see
  `/docs/self-hosted/reverse-proxy/`). This deployment binds edge (`:443`) and hub (`:8443`)
  directly with no proxy in front, so the URL **must** include `:8443` — otherwise every hub API
  call lands on the edge instead, which SNI-passthroughs and resets the connection.
- `TOWONEL_HUB_TLS_ACME_EMAIL` — Let's Encrypt registration email for the hub's own cert on
  `:8443`. This is a **real, publicly-trusted cert**, not self-signed: the agent validates it with
  standard webpki roots and does not pin via the invite token.

### The ACME chicken-and-egg bug (confirmed in source, not just observed)

Issuance uses TLS-ALPN-01 only (hardcoded upstream, no DNS-01, no static-cert file), and TLS-ALPN-01
validation always connects to port 443 — never a custom port. Read straight from
`crates/towonel-node/src/lib.rs`'s `run_node()`: in combined mode (hub+edge on one host, our setup)
`hub.run()` and `edge.run()` are **two fully independent tasks**, linked only by an in-process route
channel for tenant hostnames. The hub's ACME manager (`hub/acme.rs`) builds a correctly-wired
`CertResolver` + `EdgeAlpnSolver` (ALPN `acme-tls/1` support) — but wires it only into the hub's own
`axum_server` listener on `TOWONEL_HUB_LISTEN_ADDR` (`:8443`), never into the edge's `:443` listener.
Since Let's Encrypt's TLS-ALPN-01 validator only ever dials port 443, and port 443 is exclusively the
edge's (which has zero ACME awareness), **the hub's own cert can never be issued while both run
combined on one host** — confirmed identical on `towonel-node:1.0.1` and `1.2.0`, and reproduced with
a direct external TLS probe (`openssl s_client -alpn acme-tls/1`) timed against a live ACME challenge
window: every connection resets, in-window or not.

**Workaround (already applied on the live VPS, needed again at renewal in ~60-90 days):**
1. `systemctl stop towonel-hub`
2. Run a one-off container reusing the same `towonel-data` volume, with edge disabled so the hub can
   bind :443 directly and receive the real ACME challenge itself:
   ```sh
   docker run -d --name towonel-cert-bootstrap -p 443:443 -v towonel-data:/data \
     -e TOWONEL_EDGE_ENABLED=false \
     -e TOWONEL_HUB_LISTEN_ADDR=0.0.0.0:443 \
     -e TOWONEL_HUB_PUBLIC_URL=https://tunnel.wibrow.dev:8443 \
     -e TOWONEL_HUB_TLS_ACME_EMAIL=sam.wibrow@gmail.com \
     -e TOWONEL_DATA_DIR=/data \
     codeberg.org/towonel/towonel-node:1.2.0
   ```
3. Watch `docker logs -f towonel-cert-bootstrap` for `certificate issued successfully` (~30s).
4. `docker stop towonel-cert-bootstrap && docker rm towonel-cert-bootstrap`
5. `systemctl start towonel-hub` — the cert is already cached in the shared volume, so combined mode
   just serves it; no further validation needed until the cached cert nears expiry.

This is an upstream bug, not a config mistake — worth reporting to the towonel maintainers. Until
fixed upstream, this dance has to be repeated once per renewal window (cert validity is 90 days from
issuance; check expiry with `openssl s_client -connect tunnel.wibrow.dev:8443 ... | openssl x509
-noout -enddate`).

### Reissuing the invite token

Because the invite token embeds `TOWONEL_HUB_PUBLIC_URL`, changing that value (or fixing hub cert
issuance for the first time) means the *existing* token the agent uses is stale and must be
reissued from the hub, then updated in Infisical at
`/networking/towonel-agent/TOWONEL_INVITE_TOKEN`, then the agent pod restarted. Confirm the hub's
own cert is actually issuing successfully first — reissuing against a hub that still can't present
a valid cert just reproduces the same failure differently.

### Verify

```sh
systemctl status towonel-hub
docker logs -f towonel                                    # ACME issuance / bootstrap attempts
docker exec towonel curl -fsSk https://localhost:8443/v1/health
kubectl --context=admin@pitower -n networking logs -l app.kubernetes.io/instance=towonel-agent
```

## Secrets

```sh
sops roles/nut/vars/secrets.sops.yaml          # edit
sops -d roles/nut/vars/secrets.sops.yaml       # view
```
