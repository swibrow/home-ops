# proxmox-01 → bare-metal Talos

Replace the Proxmox VE hypervisor on proxmox-01 (Dell R630) with Talos installed directly on the
hardware, keeping the node's Kubernetes identity (`worker-07`, `10.20.10.7`) so every pinned
workload, local PV and BGP neighbour carries over unchanged. KubeVirt then runs VMs on bare metal
instead of nested inside the Proxmox VM.

## Current state

| | |
|---|---|
| Hardware | 2x Xeon E5-2687W v4 (2 NUMA nodes), 755 GiB RAM, PERC in HBA mode, UEFI |
| SSDs | 6x 745 GiB SAS (`sda`-`sdf`), `rpool`: 3 mirrors, Proxmox root + VM/CT disks |
| HDDs | 4x 559 GiB 10K SAS (`sdg`-`sdj`), `garage`: raidz1 |
| NICs | `nic1` 1G igb (`f8:bc:12:1d:46:30`): trunk, VLAN 20 tagged + untagged LAN; `nic6` 10G i40e (`3c:fd:fe:18:73:62`): VLAN 20 native |
| Guests | VM 200 `worker-07` (Talos, 364 GiB), CT 210 `garage-01` (Garage S3) |
| ZFS | 2.4.2 on the host; Talos 1.14.0 ships 2.4.3, so `garage` imports without an upgrade |

What lives where today:

| Data | Location | Fate |
|---|---|---|
| worker-07 system disk | `rpool/data/vm-200-disk-1` | Rebuilt |
| worker-07 `extra` (8 openebs-hostpath PVCs, 167G) | `rpool/data/vm-200-disk-4` (XFS in a zvol) | Copied off, restored |
| Immich library `media` (648G) | `garage/vm-200-disk-0` (XFS in a zvol) | Converted to a dataset on `garage` |
| Garage metadata (LMDB, 564M) | `rpool/data/subvol-210-disk-1` | Copied off, restored |
| Garage objects (43G) | `garage/subvol-210-disk-0` | Stays on `garage`, dataset renamed |

## Target state

| Disk(s) | Use |
|---|---|
| 2 SSDs (`V6X00TXA`, `71V0TXVX`) | Talos system disk: md RAID1 via `RAIDArrayConfig` (EPHEMERAL: images, logs, emptyDirs) |
| 4 SSDs | New pool `fast`: 2 mirrors (~1.45 TiB). Replaces `extra` and holds Garage metadata. |
| `sdg`-`sdj` | Existing `garage` raidz1, imported by the ZFS extension. Immich library + Garage objects. |

Each mirror, the boot array included, pairs one WUSTR6480 with one HUSMM3280, so a batch fault
cannot take out both sides. Talos 1.14 cannot replace a failed RAID member in place: a dead boot
disk means `talosctl wipe md` and a reinstall, which leaves the ZFS pools untouched.

Later: two NVMe drives on the PCIe card in slot 1 or 2, for storage. A dual-M.2 card needs either
x4x4 bifurcation (not yet confirmed on the R630) or its own PCIe switch.

ZFS datasets, all mounted under `/var/mnt` (Talos only allows `/var`):

| Dataset | Mountpoint | Consumer |
|---|---|---|
| `fast/extra` | `/var/mnt/extra` | `openebs-hostpath-fast` (decision 1) |
| `fast/runners` | `/var/mnt/runners` | `openebs-hostpath-runners`: amd64 CI runners, own quota so a burst stays off the TSDBs |
| `fast/garage-meta` | `/var/mnt/garage/meta` | Garage LMDB, in `meta/` |
| `garage/media` | `/var/mnt/media` | `openebs-hostpath-media` (no XFS quota, works as-is) |
| `garage/garage-data` | `/var/mnt/garage/data` | Garage blocks, in `blocks/` (renamed from `subvol-210-disk-0`) |

Existing PVs are `spec.local` with absolute paths pinned to `worker-07`. Restoring
`/var/mnt/media/openebs/local/pvc-*` to the same path means the Immich library claim needs no
change; the `extra` claims move class (decision 1). A local PV whose path is missing makes the kubelet fail the
mount instead of creating an empty directory, so a pod racing the boot-time `zpool import` retries
rather than writing under the mountpoint.

Garage moves from the LXC into the cluster: a single-replica StatefulSet pinned to `worker-07`,
hostPath-mounting the two datasets, fronted by an `envoy-internal` HTTPRoute for `s3.wibrow.dev`
(cert-manager instead of certbot on the LXC; external-dns instead of the `cloudflare-ddns` role).
The node key lives in the metadata directory, so the restored node keeps its ID and layout. Garage
mounts subdirectories of the datasets, not their roots, so an unmounted dataset makes the pod wait
instead of letting Garage initialise an empty node in a bare mountpoint.

## Pull requests

All merge during the cutover, in this order:

| PR | Change |
|---|---|
| #2741 | Talos: r630 schematic with ZFS, RAID1 boot array, worker-07 node layer, UniFi reservation, netboot MAC |
| #2742 | `openebs-hostpath-fast` / `-runners`, claims switched, `openebs-hostpath` kept off worker-07 |
| #2743 | Garage in the cluster, monitoring repointed |

## Decisions

1. **`extra` gets its own class.** `openebs-hostpath` enforces XFS project quotas and is shared with
   every node, so it cannot provision on a ZFS dataset. worker-07 gets `openebs-hostpath-fast`
   (basePath `/var/mnt/extra/openebs/local`, no `XFSQuota`); a ZFS `quota` on `fast/extra` caps the
   total. Its 8 PVCs move to the new class at cutover: `storageClassName` is immutable, so each gets
   a new claim, and the StatefulSets using `volumeClaimTemplates` (Prometheus, Victoria Metrics,
   Victoria Logs, Tempo) are deleted with `--cascade=orphan` and recreated by ArgoCD.
   `openebs-hostpath` must then stop provisioning on worker-07 (`allowedTopologies` or a taint for
   non-pinned workloads; to be settled in the PR).
2. **Metrics and logs history is kept**: the full 167G of `extra` is copied to worker-ai-01 and
   restored into the new claims.

## Phases

### 0. Preparation (no downtime)

- [x] Immich library backed up: worker-ai-01 `media/immich-library-backup`, NAS USB drive.
- [x] Garage metadata + objects backed up from `@pre-talos-migration` snapshots: worker-ai-01
      `media/garage-backup`, NAS `/volume1/backups/garage-20260928`.
- [ ] Verify both NAS copies (file count + size against worker-ai-01).
- [ ] Back up `ai/home-claude-code` and `dev/herdr-data` (no kopiur policy today): covered by the
      `extra` pre-copy. `home-claude-code` is not in git and has no consumer.
- [x] New schematic `talos/pitower/extensions/r630.yaml`: `siderolabs/zfs`, `siderolabs/intel-ucode`,
      `siderolabs/util-linux-tools` (#2741).
- [x] Rewrite `talos/pitower/node/worker-07/`: RAID1 boot array over `V6X00TXA` + `71V0TXVX`, no
      `extra`/`media` UserVolumeConfigs, `raid1` and `zfs` (`zfs_arc_max` 64 GiB) modules (#2741).
- [ ] `topf.yaml`: worker-07 `mac: 3c:fd:fe:18:73:62`, `untagged: true` (nic6, VLAN 20 native),
      schematic `@extensions/r630.yaml`.
- [ ] `terraform/unifi/reservations.tf`: worker-07 reservation to the nic6 MAC; drop `proxmox-01`
      and `garage-01`.
- [ ] Netboot menu: map `nic1` (`f8:bc:12:1d:46:30`) to worker-07. PXE only brings up maintenance
      mode; `topf apply` installs the r630 schematic.
- [ ] Garage app manifests under `kubernetes/apps/pitower/storage/garage/` (StatefulSet, config,
      Infisical secrets from `ansible/roles/garage/vars/secrets.sops.yaml`, HTTPRoute, raised
      request timeouts for multipart uploads). Kept out of `main` until cutover.
- [ ] Bulk pre-copies, done live from zvol snapshots on the Proxmox host (clone, mount read-only
      with `nouuid`):
  - `garage/vm-200-disk-0` → new dataset `garage/media` (same pool; ~648G, pool ends ~84% full
    until the zvol is destroyed).
  - `rpool/data/vm-200-disk-4` → worker-ai-01 (167G, including metrics history).
- [ ] PR (merge at cutover): `openebs-hostpath-fast` class; the 8 `extra` claims switched to it.

Merge order matters: the UniFi reservation, topf and storage-class PRs change a running node's
DHCP lease or claims, so they are prepared ahead and merged during the cutover, not before.

### 1. Cutover (downtime: media stack, monitoring, Garage-backed backups)

1. Suspend kopiur `SnapshotSchedule`s and CNPG `ScheduledBackup`s. WAL archiving queues on the
   Postgres PVCs (all on worker-05/06) until Garage is back.
2. Cordon and drain worker-07; scale down its pinned workloads (media stack, monitoring TSDBs).
3. Stop Garage; final incremental rsync of the metadata snapshot to worker-ai-01.
4. Shut down VM 200; final incremental of `media` (zvol → `garage/media`) and `extra`.
5. On the host: `zfs rename garage/subvol-210-disk-0 garage/garage-data`, set mountpoints to the
   `/var/mnt/...` paths above, clear any `sharenfs`/`sharesmb`, `zpool export garage`.
6. Reboot into PXE (untagged LAN via nic1) → Talos maintenance mode.
7. In maintenance mode, confirm `talosctl get disks --insecure` reports the serials the RAID
   selector uses. Then `mise exec -- topf apply` for worker-07 (dry-run first): Talos builds the
   RAID1 boot array and installs onto it, wiping the Proxmox root on those two disks.
8. From a privileged pod: `zpool labelclear` the four remaining old `rpool` members, create `fast`
   as two cross-model mirrors
   (`-o ashift=12 -O compression=zstd -O atime=off -O xattr=sa -O acltype=posixacl`), create
   `fast/extra`, `fast/runners` (quota 360G) and `fast/garage-meta`. Confirm `garage` was imported
   at boot. In `garage/garage-data`, move the block directories and `garage-marker` into `blocks/`.
9. Merge the storage-class PR; delete the old `extra` claims (StatefulSets `--cascade=orphan`), let
   ArgoCD create the new ones, then restore their data from worker-ai-01 into the new PV paths.
   Restore Garage metadata the same way; fix ownership (the LXC was unprivileged,
   so Garage files are owned by uid 100000+).
10. Uncordon; merge the Garage app PR; point DNS for `s3.wibrow.dev` at the gateway.
11. Verify: `garage status` (same node ID), `garage bucket list`, a kopiur snapshot and a CNPG
    backup succeed, WAL archive catches up, Immich shows the library, pinned pods Running, BGP
    session for 10.20.10.7 established.
12. Resume schedules.

### 2. Cleanup

- `terraform/proxmox`: `removed` blocks for VM 200, CT 210 and the downloads (the API is gone),
  then delete the stack, `.github/workflows/terraform-proxmox.yaml`, and `PROXMOX_VE_*` in `mise.toml`.
- Ansible: drop the `proxmox`, `garage`, `garage-tls` hosts/roles and `cloudflare-ddns` for
  `s3.wibrow.dev`.
- Monitoring: Garage `ScrapeConfig` and blackbox probes to the in-cluster service.
- `extensions/proxmox.yaml` if nothing else uses it; stale Terraform comments about sizes.
- `AGENTS.md`: Volsync → kopiur; Garage runs in-cluster.
- Destroy `@pre-talos-migration` snapshots and the worker-ai-01 backup PVCs once the new setup has
  a week of good backups.

## Rollback

Until step 7 nothing on proxmox-01 is destroyed: power it back on, boot Proxmox, start VM 200 and
CT 210, and resume schedules. After step 7, `garage` still holds the Immich library and Garage
objects; the metadata and `extra` restore from worker-ai-01 and the NAS copies.

## Risks

- Garage is the only backup target for kopiur and CNPG. During the window there are no new backups,
  and a failed metadata restore makes the existing ones unreadable, hence the two off-host copies.
- `garage` is 4 drives with ~8.9 years of power-on time and one grown defect; raidz1 survives one
  failure. The migration adds a full read of `media` plus a write of the same size.
- The ZFS module follows the Talos kernel: every upgrade must use the r630 schematic.
- ARC is invisible to kubelet memory accounting; `zfs_arc_max` keeps it bounded.
- Pool scrubs and SMART alerts were Proxmox/ZED's job; replace with a scrub CronJob and alerts.
