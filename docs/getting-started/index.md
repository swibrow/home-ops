# Getting Started

Welcome to the home lab documentation. This section will help you understand what this repository contains, how it is organized, and how to get up and running.

---

## What This Repository Contains

The [home-ops](https://github.com/swibrow/home-ops) repository is the single source of truth for the Kubernetes cluster. Everything from the operating system configuration to application deployments is declared in code and managed through GitOps.

The repository includes:

- **Talos Linux machine configurations** -- patches, secrets, and extension definitions for every node in the cluster
- **Kubernetes manifests** -- organized by category (networking, media, security, monitoring, and more), deployed via ArgoCD ApplicationSets
- **ArgoCD definitions** -- the ApplicationSet resources that wire each app category to the cluster
- **Bootstrap resources** -- initial resources needed to bring the cluster from zero to a running state
- **Documentation** -- this MkDocs Material site, covering architecture, operations, and reference material

---

## How to Browse the Documentation

The documentation is organized into sections that mirror the layers of the infrastructure:

| Section | What you will find |
|:--------|:-------------------|
| **Getting Started** | Prerequisites, architecture overview, and this orientation page |
| **Infrastructure** | Hardware inventory, Talos Linux configuration, cluster bootstrap, and node management |
| **Networking** | Cilium CNI, Envoy Gateway, DNS management, Cloudflare Tunnel, Tailscale VPN, and load balancers |
| **GitOps** | ArgoCD setup, ApplicationSet patterns, sync policies, and how to add new apps |
| **Storage** | Rook Ceph distributed storage, OpenEBS local volumes, and backup/restore procedures |
| **Security** | Authentication (Authelia, LLDAP), secret management (SOPS, External Secrets, 1Password Connect), and TLS certificates |
| **Monitoring** | Prometheus stack, Grafana dashboards, Loki log aggregation, and Fluent Bit |
| **Applications** | Media stack (Jellyfin, *arr apps), home automation (Home Assistant, Zigbee2MQTT), and self-hosted services |
| **Operations** | Day-to-day tasks: justfile recipes, Talos commands, troubleshooting guides, and upgrade procedures |
| **CI/CD** | GitHub Actions workflows, container image builds, and Renovate dependency management |
| **Reference** | IP allocation table and a full catalog of deployed applications |

!!! note "Navigation"
    Use the **tabs** at the top to jump between major sections, or use the **search bar** to find specific topics. The sidebar expands to show all pages within the current section.

---

## Next Steps

<div class="grid cards" markdown>

-   **Prerequisites**

    ---

    Tools, access, and network requirements you need before working with this cluster.

    [:octicons-arrow-right-24: Prerequisites](prerequisites.md)

-   **Architecture Overview**

    ---

    Understand the full stack from hardware to applications, including network traffic flows.

    [:octicons-arrow-right-24: Architecture Overview](architecture-overview.md)

</div>
