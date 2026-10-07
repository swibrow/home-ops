# Getting Started

Welcome to the home lab documentation. This section will help you understand what this repository contains, how it is organized, and how to get up and running.

---

## What This Repository Contains

The [home-ops](https://github.com/swibrow/home-ops) repository is the single source of truth for the `pitower` Kubernetes cluster. Everything from the operating system configuration to application deployments is declared in code and managed through GitOps.

The repository includes:

- **Talos Linux machine configurations** (`talos/pitower/`): the [topf](https://github.com/postfinance/topf) cluster definition, layered config patches, SOPS-encrypted secrets, and Image Factory schematics for every node type
- **Kubernetes manifests** (`kubernetes/apps/pitower/`): one directory per app, grouped by category (networking, media, security, monitoring, and more), deployed by a single ArgoCD ApplicationSet
- **ArgoCD definitions** (`kubernetes/argocd/`, `kubernetes/bootstrap/`): the ApplicationSets and the self-managed ArgoCD installation
- **Reusable kustomize components** (`kubernetes/components/`): kopiur backups, PVCs, and shared CNPG database credentials
- **Terraform** (`terraform/`): AWS, Cloudflare, UniFi (networks, DHCP reservations, BGP), and more
- **Ansible** (`ansible/`): hosts outside the cluster, such as the NUT server and the towonel hub
- **Documentation**: this site: Markdown in `docs/`, built with Astro from `site/`, covering architecture, operations, and reference material

---

## How to Browse the Documentation

The documentation is organized into sections that mirror the layers of the infrastructure:

| Section | What you will find |
|:--------|:-------------------|
| **Getting Started** | Prerequisites, architecture overview, and this orientation page |
| **Infrastructure** | Hardware inventory, Talos Linux configuration, cluster bootstrap, and node management |
| **Networking** | Cilium CNI, Envoy Gateway, DNS management, towonel tunnel, Tailscale VPN, and load balancers |
| **GitOps** | ArgoCD setup, ApplicationSet patterns, sync policies, and how to add new apps |
| **Storage** | Rook Ceph, OpenEBS local volumes, Garage S3, and backup/restore with kopiur |
| **Security** | Authentication (Kanidm), secret management (External Secrets with Infisical, SOPS), and TLS certificates |
| **Monitoring** | Prometheus stack, Grafana dashboards, VictoriaMetrics, VictoriaLogs, Fluent Bit, and OpenTelemetry |
| **Applications** | Media stack (Jellyfin, *arr apps), home automation (Home Assistant, Frigate), and self-hosted services |
| **Operations** | Day-to-day tasks: justfile recipes, Talos commands, troubleshooting guides, and upgrade procedures |
| **CI/CD** | GitHub Actions workflows, container image builds, and Renovate dependency management |
| **Reference** | IP allocation table and a full catalog of deployed applications |

> [!NOTE]
> **Navigation**
>
> Use the section links at the top to jump between major sections, or search to find specific topics. The sidebar lists every page in the current section.

---

## Next Steps

- [Prerequisites](prerequisites.md): tools, access, and network requirements you need before working with this cluster.
- [Architecture Overview](architecture-overview.md): the full stack from hardware to applications, including network traffic flows.
