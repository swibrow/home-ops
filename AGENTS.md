# Home-Ops

Kubernetes home lab GitOps repository.

## Stack

- **Talos Linux** — immutable Kubernetes OS
- **ArgoCD** — GitOps continuous delivery
- **Cilium** — CNI with L2 announcements + BGP to the UniFi gateway (LoadBalancer IPs: 10.20.10.128-255)
- **Envoy Gateway** — ingress (external/internal/direct gateways)
- **CloudNativePG** — PostgreSQL operator
- **kopiur** — PVC snapshots (Kopia) to Garage S3
- **External Secrets** — Infisical + CNPG ClusterSecretStores
- **External DNS** — Cloudflare DNS management

## Domain

`wibrow.dev` via Cloudflare

## App Structure

```
kubernetes/apps/{cluster}/{category}/{app}/
├── kustomization.yaml   # namespace, pvc/kopiur components, helmCharts generator
├── values.yaml          # app-template helm values
└── externalsecret.yaml  # optional: Infisical + CNPG secrets
```

- One ApplicationSet per cluster using git directory generator: `kubernetes/apps/{cluster}/*/*`
- App naming: `{cluster}-{category}-{app}` from path segments
- Namespace derived from category
- Helm chart: `app-template` (bjw-s-labs) v4.6.2 via `oci://ghcr.io/bjw-s-labs/helm`

## Key Conventions

- **Routes** use Gateway API (`HTTPRoute`) with `parentRefs` to `envoy-internal`, `envoy-external`, or `envoy-direct` in namespace `networking`, sectionName `https`
- **Databases** use CNPG clusters defined in `kubernetes/apps/pitower/cloudnative-pg/cluster/cluster.yaml`, accessed via `cnpg-secrets` ClusterSecretStore
- **App secrets** stored in Infisical at `/category/app/SECRET_NAME`
- **kopiur** backups via reusable kustomize component at `kubernetes/components/kopiur`, configured per-app with a `kopiur-config` ConfigMap (`APP_NAME`, `CLAIM_NAME`); repository is the `garage` ClusterRepository
- **Timezone**: `Europe/Zurich`
- **Reloader** annotation `reloader.stakater.com/auto: "true"` on controllers that consume secrets

## Analytics

[Rybbit](https://insights.wibrow.dev) (self-hosted) at `kubernetes/apps/pitower/analytics/rybbit/`. Backend + client + ClickHouse; tracking script is served at `https://insights.wibrow.dev/api/script.js`.

To track a site, embed the snippet in the page `<head>` (get `data-site-id` from the Rybbit dashboard):

```html
<script src="https://insights.wibrow.dev/api/script.js" data-site-id="<id>" defer></script>
```

- **Per-app (preferred)**: use the app's own injection hook. Homepage exposes `custom.js` (`<Script src="/api/config/custom.js"/>`) — drop a loader in the configmap and mount it at `/app/config/custom.js` (see `apps/pitower/selfhosted/homepage/`). Same-origin, client-side, no proxy tricks.
- **Gateway-wide injection** (only when the app has no hook): attach an `EnvoyExtensionPolicy` (Lua, EG v1.8.0) to the target `HTTPRoute` under `networking`. The Lua `envoy_on_response` checks `content-type` for `text/html` and inserts the `<script>` before `</head>` via `body:setBytes()`. **Caveat: compression breaks it** — browsers send `Accept-Encoding: br/gzip`, so the Lua sees compressed bytes and the `</head>` match silently fails (curl without `--compressed` misleadingly works). You'd have to strip `Accept-Encoding` on the request path, losing compression. Prefer the app-native hook.

## Bootstrap

- ArgoCD + ApplicationSets at `kubernetes/bootstrap/`
- CNPG operator + clusters at `kubernetes/apps/pitower/cloudnative-pg/`

## Infrastructure

- Main cluster: `pitower`. Nodes `worker-01`..`10` and `worker-ai-01` are `10.20.10.1`-`11` on VLAN 20; `worker-01`..`03` are the control planes behind the API VIP `10.20.10.0`
- Talos configs live at the repo root under `talos/<cluster>/` — lifecycle managed with [topf](https://github.com/postfinance/topf) (`topf.yaml` + layered patches in `all/`, `control-plane/`, `node/<host>/`; secrets stay SOPS-encrypted, decrypted by topf with the age key the root `mise.toml` points `SOPS_AGE_KEY_FILE` at). Run it as `mise exec -- topf ...` from `talos/pitower`; `apply` prompts y/n per node, so review `--dry-run` first and pass the global `--confirm=false` when running non-interactively. `talosctl` only for diagnostics.
- worker-07 is a bare-metal Dell R630 (ex proxmox-01): Talos on an md RAID1 of two SSDs (`RAIDArrayConfig`, selected by `disk.wwid`; behind the PERC in HBA mode Talos sees no disk serials) and two ZFS pools imported by the `zfs` extension: `fast` (4 SSDs, two mirrors: `/var/mnt/extra`, `/var/mnt/runners`, Garage metadata) and `hdd` (4x 10K SAS raidz1: `/var/mnt/media`, Garage blocks). Storage classes `openebs-hostpath-fast` / `-runners` / `-media` only provision there; `openebs-hostpath` (XFS quotas) is kept off it. Record of the move: `docs/infrastructure/proxmox-01-migration.md`.
- ZFS admin on worker-07: Talos has no shell, so run the host tools from a privileged `hostPID` pod: `nsenter -t 1 -m -- /usr/local/sbin/zpool ...`. Exporting a pool first needs that node's Multus pod restarted (its `/hostroot` bind pins every mount under `/var/mnt`), and no dataset may mount outside `/var`.
- New Talos schematics must be submitted to the Image Factory (`curl -X POST --data-binary @<schematic>.yaml https://factory.talos.dev/schematics`) before an install; topf only computes the ID locally, and the installer image 404s otherwise.
- The self-hosted `home-ops` CI runners are pinned to worker-07. While it is drained or down, workflows on them queue, so plan and apply Terraform/topf locally; the Talos Apply workflow also runs `topf apply` for the whole cluster on every merge that touches `talos/`.
- Terraform: `terraform/` (AWS, Cloudflare, UniFi, etc.). `terraform/unifi` plans on PRs and applies on merge to `main` via the Terraform UniFi workflow
- `mise.toml` env: `KUBECONFIG` is `~/.kube/pitower.yaml` (the default `~/.kube/config` is a different cluster). `UNIFI_*` credentials live in `terraform/mise.toml`, so UniFi commands must run under `terraform/`

## Networking

- **VLAN 20 (`servers`, `10.20.0.0/16`)**: `10.20.0.0`-`10.20.199.255` is static (nodes, API VIP, LB pool, Multus pod IPs, reservations in `terraform/unifi/reservations.tf`); DHCP hands out `10.20.200.1`-`10.20.255.254` (`terraform/unifi/networks.tf`). The untagged LAN is `192.168.0.0/24`.
- **LoadBalancer IPs**: Cilium LB-IPAM pool `10.20.10.128`-`255`, pinned per Service with `lbipam.cilium.io/ips`. Announced two ways at once: L2 (ARP, needed because the pool is inside VLAN 20) and BGP (`kubernetes/apps/pitower/kube-system/cilium/config/cilium-bgp.yaml`, cluster ASN 64513, worker-ai-01 excluded) to the UCG Fiber (ASN 64512).
- **Pod IPs are routable**: native routing (no tunnel), and each node's `/24` from `10.244.0.0/16` is advertised over the same BGP session, so the LAN reaches pods directly via the gateway (except on worker-ai-01, which does not peer). Pod egress is still masqueraded to the node IP.
- **IPv6 (dual-stack, IPv4 primary)**: Init7 delegates `2a02:16a:2a0a::/56`; VLAN 20 is PD slice 2 (`2a02:16a:2a0a:2::/64`), so nodes SLAAC an EUI-64 address there (the gateway is `::1`). Pods are ULA `fd10:244::/56` (a `/64` per node, masqueraded to the node address on egress), Services `fd10:96::/112`, and the LB pool's IPv6 block is slice 3 (`2a02:16a:2a0a:3::/112`), reachable only via BGP. IPv6 routes ride a separate BGP session (`ucg-v6`); the gateway accepts any VLAN 20 address via `bgp listen range`. Services stay IPv4-only unless they set `ipFamilyPolicy`. `spec.podCIDRs` is immutable, so a node registered before a pod subnet change keeps its old CIDRs until its Node object is deleted and kubelet restarted.
- **Gateway BGP config**: `terraform/unifi/frr-bgp.conf`, pushed with `mise run unifi:bgp-upload` from `terraform/` (the UniFi provider has no BGP resource). Its neighbor list names each node IP, so adding or renumbering a node means editing it and re-running the task.
- **Multus** (thick, `kube-system/multus`) adds secondary pod interfaces; Cilium stays primary and needs `cni.exclusive: false`. Attachments use macvlan with static IPAM, so each pod sets its own IP: `k8s.v1.cni.cncf.io/networks: '[{"name":"vlan20","namespace":"kube-system","ips":["10.20.x.y/16"]}]'`.
  - `kube-system/vlan20`: VLAN 20 on every node (macvlan on the default-route link).
  - `networking/lan`: untagged LAN on `enp0s25` (worker-05/06 only); netboot serves PXE from `192.168.0.248` on it.
  - Caveats: traffic on `net1` bypasses Cilium policy and Hubble; a pod cannot reach its own node over macvlan; normal cluster pods cannot reach a pod's `net1` address from another subnet (asymmetric return path).
  - If pods lose `net1` after a Cilium rollout, check `/etc/cni/net.d` for `00-multus.conf.cilium_bak` and restart that node's Multus pod.

## Task Tracking

All TODOs, planned work, and follow-ups for this repo are tracked on the GitHub project board: <https://github.com/users/swibrow/projects/4>.

- Do not scatter TODOs in code comments, issues, or memory — create/update items on the board.
- Use `gh project` CLI (owner `swibrow`, project number `4`) to list/add/update items.
- Requires `project` scope: `gh auth refresh -s project` if missing.
