<div align="center">

# Home Ops

### Kubernetes Home Lab powered by Talos Linux and managed with ArgoCD

[![Talos](https://img.shields.io/badge/Talos-v1.14.0-blue?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyTDIgN3Y2YzAgNS41NSA0LjI4IDEwLjc0IDEwIDEyIDUuNzItMS4yNiAxMC02LjQ1IDEwLTEyVjdsLTEwLTV6Ii8+PC9zdmc+)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36.1-blue?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Cilium](https://img.shields.io/badge/Cilium-v1.20.2-blue?style=for-the-badge&logo=cilium&logoColor=white)](https://cilium.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-chart%20v10.9.6-blue?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/cd/)

[![GitHub Actions](https://img.shields.io/github/actions/workflow/status/swibrow/home-ops/checks.yaml?branch=main&label=Checks&style=for-the-badge&logo=github)](https://github.com/swibrow/home-ops/actions/workflows/checks.yaml)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-brightgreen?style=for-the-badge&logo=renovatebot&logoColor=white)](https://github.com/swibrow/home-ops/issues?q=is%3Aissue+label%3Arenovate)

[![License](https://img.shields.io/github/license/swibrow/home-ops?style=for-the-badge&color=green)](https://github.com/swibrow/home-ops/blob/main/LICENSE)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/swibrow/home-ops?style=for-the-badge&logo=git&logoColor=white)](https://github.com/swibrow/home-ops/commits/main)

</div>

---

## Overview

This repository is the single source of truth for my Kubernetes home lab. Everything from the operating system to application deployments is declared in code and reconciled through GitOps.

| | |
|:--|:--|
| **OS** | [Talos Linux](https://www.talos.dev/): immutable, API-driven, secure-by-default (lifecycle managed with [topf](https://github.com/postfinance/topf)) |
| **CNI** | [Cilium](https://cilium.io/): eBPF networking, kube-proxy replacement, native routing, L2 + BGP announcements, dual-stack; [Multus](https://github.com/k8snetworkplumbingwg/multus-cni) for secondary VLAN interfaces |
| **GitOps** | [ArgoCD](https://argoproj.github.io/cd/): ApplicationSets with a Git directory generator |
| **Ingress** | [Envoy Gateway](https://gateway.envoyproxy.io/): two gateways (external, internal) via the Gateway API |
| **Storage** | [Rook Ceph](https://rook.io/) (distributed block) + [OpenEBS](https://openebs.io/) (local hostpath, ZFS-backed on worker-07) + [Garage](https://garagehq.deuxfleurs.fr/) (S3) |
| **Database** | [CloudNativePG](https://cloudnative-pg.io/) (PostgreSQL) + [Dragonfly](https://www.dragonflydb.io/) + [ClickHouse](https://clickhouse.com/) |
| **Secrets** | [External Secrets](https://external-secrets.io/) (Infisical + CNPG ClusterSecretStores) + [SOPS](https://github.com/getsops/sops) (age) |
| **Auth** | [Kanidm](https://kanidm.com/): standalone OIDC / OAuth2 identity provider (+ LDAP) |
| **Certs** | [cert-manager](https://cert-manager.io/) with Let's Encrypt DNS-01 |
| **DNS** | [external-dns](https://github.com/kubernetes-sigs/external-dns) for Cloudflare and UniFi; public ingress through a towonel tunnel |
| **Backups** | kopiur: PVC snapshots with [Kopia](https://kopia.io/) to Garage S3; CNPG via the Barman Cloud plugin |
| **Monitoring** | kube-prometheus-stack (Prometheus / Alertmanager) + Grafana Operator + VictoriaMetrics + VictoriaLogs + Fluent Bit + Tempo + Gatus + ntfy |
| **VMs** | [KubeVirt](https://kubevirt.io/) + CDI |
| **GPU** | NVIDIA DRA driver on worker-ai-01 (RTX 3090 Ti) |

> [!TIP]
> **Full documentation**: [swibrow.github.io/home-ops](https://swibrow.github.io/home-ops)
>
> **Domain**: `wibrow.dev` (managed via Cloudflare)

## Clusters

`pitower` is the sole cluster: the main workload cluster, self-hosting its own ArgoCD and Kanidm.

| Cluster | Role | Endpoint |
|:--------|:-----|:---------|
| `pitower` | Main workload cluster (11 nodes) | `https://10.20.10.0:6443` (VIP) |

### `pitower` Nodes

| Node | Role | IP | Hardware |
|:-----|:-----|:---|:---------|
| worker-01 | Control Plane | 10.20.10.1 | AMD Ryzen |
| worker-02 | Control Plane | 10.20.10.2 | AMD Ryzen |
| worker-03 | Control Plane | 10.20.10.3 | AMD Ryzen |
| worker-04 | Worker | 10.20.10.4 | Intel (iGPU, `dedicated=media-home` taint) |
| worker-05 | Worker | 10.20.10.5 | Intel |
| worker-06 | Worker | 10.20.10.6 | Intel |
| worker-07 | Worker | 10.20.10.7 | Dell R630, bare metal (ZFS: `fast` SSD mirrors, `hdd` raidz1) |
| worker-08 | Worker | 10.20.10.8 | Raspberry Pi (arm64) |
| worker-09 | Worker | 10.20.10.9 | Raspberry Pi (arm64) |
| worker-10 | Worker | 10.20.10.10 | Raspberry Pi (arm64) |
| worker-ai-01 | Worker | 10.20.10.11 | NVIDIA RTX 3090 Ti (GPU workloads) |

### Network

| Device | Purpose |
|:-------|:--------|
| UniFi Cloud Gateway Fiber | Router, VLANs, BGP peer for LoadBalancer and pod routes |
| UniFi switching + U7-Pro / U6-Lite | Switching and wireless |
| towonel tunnel | Public ingress (`*.wibrow.dev` to `envoy-external`) |

Nodes live on VLAN 20 (`10.20.0.0/16`), dual-stack with IPv6 from the Init7 delegated prefix. Cilium runs in native routing mode and serves LoadBalancer IPs from `10.20.10.128-255`, announced over L2 (ARP) and BGP (ASN 64513 to the gateway's 64512, config in `terraform/unifi/frr-bgp.conf`); each node's pod CIDR is advertised too, so pods are routable from the LAN. Envoy gateways: `envoy-external` (`10.20.10.239`, towonel tunnel) and `envoy-internal` (`10.20.10.238`).

### Storage

| Device | Purpose |
|:-------|:--------|
| Synology NAS | Media and bulk data (NFS) |
| Rook Ceph | Distributed block storage (`ceph-block`, default StorageClass) |
| worker-07 ZFS pools | OpenEBS hostpath (`-fast`, `-media`, `-runners`) and Garage S3 |
| Local SSD | Talos OS + OpenEBS hostpath volumes |

![Server rack](images/rack.jpg)

## Repository Structure

```
home-ops/
├── .github/workflows/   # CI: checks, ArgoCD diff, Talos diff/apply, Terraform, image builds, docs
├── .justfiles/          # Just task runner recipes
├── 3d-prints/           # Rack mounts and other printed parts
├── ansible/             # Host provisioning
├── docker/              # Container images that can't live in cloudsnacks/containers
├── docs/                # Documentation pages (Markdown, readable on GitHub)
├── iot/                 # ESPHome, Home Assistant, Button+ configs
├── kubernetes/
│   ├── apps/            # Application manifests: {cluster}/{category}/{app}
│   ├── argocd/          # ApplicationSets (per cluster)
│   ├── bootstrap/       # ArgoCD bootstrap
│   └── components/      # Reusable kustomize components (kopiur, pvc, cnpg-db-shared)
├── talos/               # Talos configs per cluster (topf-managed, SOPS-encrypted)
├── terraform/           # AWS, Cloudflare, UniFi, etc.
├── workers/status/      # status.wibrow.dev (Cloudflare Worker, outside the cluster on purpose)
├── scripts/             # Helper scripts
├── site/                # Astro site that builds docs/ into swibrow.github.io/home-ops
├── mise.toml            # Tooling and env (KUBECONFIG, SOPS key)
└── renovate.json5       # Dependency management
```

## GitOps

Cluster state is reconciled by ArgoCD. Each cluster has one ApplicationSet using a Git directory generator over `kubernetes/apps/{cluster}/*/*`: every `{category}/{app}` directory is discovered automatically, deployed as `{cluster}-{category}-{app}` into a namespace derived from its category.

Most apps are rendered from the [`app-template`](https://github.com/bjw-s-labs/helm) chart (bjw-s-labs) via a helm chart generator. The `pitower` cluster spans these categories:

```
kubernetes/apps/pitower/
├── ai/                  # agentgateway, Open WebUI, ToolHive, agent-sandbox, ComfyUI, MLflow, SearXNG
├── analytics/           # Rybbit
├── arc/                 # GitHub Actions runner controller + runners
├── banking/             # Actual, Firefly III, Ghostfolio, Paperless
├── cert-manager/        # TLS certificate automation
├── database/            # CNPG operator + clusters, Barman Cloud plugin, Dragonfly, ClickHouse
├── dev/                 # Forgejo, dev desktop, herdr
├── home-automation/     # Home Assistant, Frigate
├── kopiur-system/       # kopiur operator + Garage repository
├── kube-system/         # Cilium, CoreDNS, Multus, metrics-server
├── kubevirt/            # KubeVirt + CDI
├── media/               # Jellyfin, Immich, Sonarr, Radarr, Prowlarr, autobrr, qBittorrent, SABnzbd
├── monitoring/          # kube-prometheus-stack, VictoriaMetrics/Logs, Grafana, Tempo, Gatus, ntfy, exporters
├── networking/          # Envoy Gateway, external-dns, towonel, Tailscale, netboot
├── openebs/             # Local hostpath provisioner
├── renovate/            # Renovate operator
├── rook-ceph/           # Distributed storage
├── second-brain/        # AFFiNE, CouchDB
├── security/            # Kanidm, External Secrets, CrowdSec, RBAC
├── selfhosted/          # Homepage, Glance, Miniflux, Mealie, n8n, Atuin, Excalidraw, and more
├── system/              # Garage, Reloader, KEDA, Headlamp, Spegel, NVIDIA DRA, Intel device plugins
├── vms/                 # KubeVirt virtual machines
├── workflows/           # Argo Workflows + Argo Events
└── workshop/            # Bambuddy
```

Adding a new application is as simple as creating a directory: ArgoCD discovers and deploys it automatically.

## Acknowledgements

Shout out to the [Home Operations](https://discord.com/invite/home-operations) community and [Uptime Lab](https://uplab.pro/).
