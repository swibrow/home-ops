---
title: Storage
---

# Storage

The cluster uses a layered storage architecture to match workload requirements with the right storage backend. Distributed block storage, node-local volumes, and NAS-backed NFS mounts each serve a distinct purpose.

## Architecture

```mermaid
flowchart TD
    Apps[Applications] -->|PersistentVolumeClaim| SC{StorageClass}

    SC -->|ceph-block| RC[(Rook Ceph\n3x ~500GB SATA SSD\nReplicated Block)]
    SC -->|openebs-hostpath| OE[(OpenEBS\nLocal PV\nNode-Local Disk)]
    SC -->|openebs-hostpath-fast / -runners / -media| ZFS[(worker-07 ZFS\nfast: SSD mirrors\nhdd: SAS raidz1)]
    SC -->|openebs-hostpath-models| AI[(worker-ai-01\nNVMe)]
    Apps -->|inline nfs volume| SYN[(Synology NAS\n4-Bay 8TB\nNFS server data)]

    RC -->|CephBlockPool| OSD1[worker-01\nSSD OSD]
    RC -->|CephBlockPool| OSD2[worker-02\nSSD OSD]
    RC -->|CephBlockPool| OSD3[worker-03\nSSD OSD]

    subgraph Backup
        KOP[kopiur] -->|Kopia snapshots| GAR[(Garage S3\non worker-07)]
        SNAP[Snapshot Controller] -->|CSI Snapshots| RC
    end
```

## Storage Classes

| StorageClass | Provider | Replicated | Use Case |
|:-------------|:---------|:----------:|:---------|
| `ceph-block` (default) | Rook Ceph | Yes (3x) | General-purpose workloads requiring high availability |
| `openebs-hostpath` | OpenEBS | No | Databases and workloads needing low-latency local disk (every node except worker-07) |
| `openebs-hostpath-fast` | OpenEBS on worker-07 `fast/extra` | ZFS mirrors | Workloads pinned to worker-07 (monitoring TSDBs, media apps) |
| `openebs-hostpath-runners` | OpenEBS on worker-07 `fast/runners` | ZFS mirrors | amd64 CI runner scratch, quota-bounded together |
| `openebs-hostpath-media` | OpenEBS on worker-07 `hdd/media` | ZFS raidz1 | Immich photo library (Retain) |
| `openebs-hostpath-models` | OpenEBS on worker-ai-01 NVMe | No | LLM weights and AI scratch |
| none (inline `type: nfs`) | Synology NAS (`data`) | RAID | Media library (`/volume1/media`) and Frigate recordings (`/volume1/cctv`) |

## When to Use Each

> [!TIP]
> **Choosing a StorageClass**
>
> - **Rook Ceph** -- Default choice for most workloads. Data is replicated across three SATA SSDs on worker-01/02/03, surviving single-node failures. Use for application databases, config volumes, and anything that needs to survive rescheduling.
>
> - **OpenEBS** -- Best for workloads that manage their own replication (e.g., PostgreSQL with CloudNativePG) or need the lowest possible latency. Data lives on a single node and is **not** replicated by the storage layer. The `-fast`, `-runners` and `-media` classes only provision on worker-07, `-models` only on worker-ai-01.
>
> - **Synology NFS** -- Large media libraries. Apps mount the NAS export directly as an app-template `type: nfs` volume (`server: data`); there is no NFS StorageClass or provisioner.

## Components

| Component | Namespace | Purpose |
|:----------|:----------|:--------|
| [Rook Ceph](rook-ceph.md) | `rook-ceph` | Distributed block storage on SATA SSDs |
| [OpenEBS](openebs.md) | `openebs` | Local PV provisioner for node-local storage |
| [kopiur](backup-restore.md#kopiur) | `kopiur-system` | PVC snapshots (Kopia) to Garage |
| [Snapshot Controller](backup-restore.md#csi-snapshots) | `system` | CSI volume snapshots |
| [Garage S3](garage.md) | `system` | S3-compatible object store on worker-07's ZFS pools |

## Sections

| Page | Description |
|:-----|:------------|
| [Rook Ceph](rook-ceph.md) | Distributed Ceph cluster -- operator, CSI drivers, cluster config, storage classes |
| [OpenEBS](openebs.md) | Local PV provisioner and the hostpath storage classes |
| [Garage S3](garage.md) | S3-compatible object store (backup target for kopiur and CNPG) -- setup, usage, and operations |
| [Backup & Restore](backup-restore.md) | kopiur and CNPG backups to Garage, CSI snapshots, restore procedures, what is not backed up |
