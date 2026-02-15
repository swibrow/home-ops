---
title: Infrastructure
---

# Infrastructure

The cluster runs on a mix of ARM and x86 hardware, managed entirely through [Talos Linux](https://www.talos.dev/) -- an immutable, API-driven Kubernetes OS. This section covers the physical and logical layers that make up the cluster.

## Overview

```mermaid
graph TD
    subgraph Network
        SW[TP-Link 24-Port PoE Switch]
        RT[NanoPi R5C Router]
        AP1[Ubiquiti U7-Pro AP]
        AP2[Ubiquiti U6-Lite AP]
    end

    subgraph Control Plane
        CP1[worker-01<br/>Lenovo 440p]
        CP2[worker-02<br/>Lenovo 440p]
        CP3[worker-03<br/>Acemagician AM06]
    end

    subgraph Workers
        W4[worker-04<br/>Acemagician AM06]
        W5[worker-05<br/>Acemagician AM06]
        W6[worker-06<br/>Acemagician AM06]
        WP1[worker-pi-01<br/>Raspberry Pi 4]
        WP2[worker-pi-02<br/>Raspberry Pi 4]
        WP3[worker-pi-03<br/>Raspberry Pi 4]
    end

    subgraph Storage
        SYN[Synology 4-Bay NAS<br/>8TB]
        CEPH[(Ceph on NVMe)]
    end

    SW --> CP1 & CP2 & CP3
    SW --> W4 & W5 & W6
    SW --> WP1 & WP2 & WP3
    SW --> SYN
    RT --> SW
    UPS[Eaton 500VA UPS] -.-> SW & RT
```

## Sections

| Page | Description |
|------|-------------|
| [Hardware](hardware.md) | Full hardware inventory -- compute nodes, network gear, and storage |
| [Talos Linux](talos-linux.md) | Talos OS configuration, factory images, extensions, and patches |
| [Cluster Bootstrap](cluster-bootstrap.md) | Step-by-step guide to bootstrapping the cluster from scratch |
| [Node Management](node-management.md) | Day-2 operations: applying configs, rebooting, resetting, and upgrading nodes |

## Key Design Decisions

- **Talos Linux** was chosen over traditional distributions for its immutability, minimal attack surface, and fully API-driven management (no SSH, no shell).
- **Mixed architecture** (ARM + x86) is supported through Talos factory images with per-node schematics and extensions.
- **Control plane nodes also run workloads** (`allowSchedulingOnControlPlanes: true`) to maximize resource utilization.
- **Cilium** replaces kube-proxy entirely and serves as the CNI, configured at bootstrap time via kustomize addons.
- **PoE** powers the Raspberry Pi nodes directly from the switch, reducing cable clutter.
