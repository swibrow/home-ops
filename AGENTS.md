# Home-Ops

Kubernetes home lab GitOps repository.

## Stack

- **Talos Linux** — immutable Kubernetes OS
- **ArgoCD** — GitOps continuous delivery
- **Cilium** — CNI with L2 announcements + BGP to the UniFi gateway (LoadBalancer IPs: 10.20.10.128-255)
- **Envoy Gateway** — ingress (external/internal/direct gateways)
- **CloudNativePG** — PostgreSQL operator
- **Volsync** — PVC backup to S3
- **External Secrets** — Infisical + CNPG ClusterSecretStores
- **External DNS** — Cloudflare DNS management

## Domain

`wibrow.dev` via Cloudflare

## App Structure

```
kubernetes/apps/{cluster}/{category}/{app}/
├── kustomization.yaml   # namespace, volsync component, helmCharts generator
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
- **Volsync** backups via reusable kustomize component at `kubernetes/components/volsync`, configured per-app with `volsync-config` ConfigMap
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
- Terraform: `terraform/` (AWS, Cloudflare, UniFi, etc.). `terraform/unifi` plans on PRs and applies on merge to `main` via the Terraform UniFi workflow
- `mise.toml` env: `KUBECONFIG` is `~/.kube/pitower.yaml` (the default `~/.kube/config` is a different cluster). `UNIFI_*` credentials live in `terraform/mise.toml`, so UniFi commands must run under `terraform/`

## Networking

- **VLAN 20 (`servers`, `10.20.0.0/16`)**: `10.20.0.0`-`10.20.199.255` is static (nodes, API VIP, LB pool, Multus pod IPs, reservations in `terraform/unifi/reservations.tf`); DHCP hands out `10.20.200.1`-`10.20.255.254` (`terraform/unifi/networks.tf`). The untagged LAN is `192.168.0.0/24`.
- **LoadBalancer IPs**: Cilium LB-IPAM pool `10.20.10.128`-`255`, pinned per Service with `lbipam.cilium.io/ips`. Announced two ways at once: L2 (ARP, needed because the pool is inside VLAN 20) and BGP (`kubernetes/apps/pitower/kube-system/cilium/config/cilium-bgp.yaml`, cluster ASN 64513, worker-ai-01 excluded) to the UCG Fiber (ASN 64512).
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
