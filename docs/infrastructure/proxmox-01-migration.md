# proxmox-01 → bare-metal Talos

**Done 2026-09-28.** The Proxmox VE hypervisor on proxmox-01 (Dell R630) was replaced with Talos
installed directly on the hardware. The node kept its Kubernetes identity (`worker-07`,
`10.20.10.7`), so pinned workloads, local PVs and the BGP neighbour carried over. Garage moved from
an LXC on the host into the cluster (`system/garage`). KubeVirt VMs on worker-07 now run on bare
metal instead of nested inside a Proxmox VM.

## Before

| | |
|---|---|
| Hardware | 2x Xeon E5-2687W v4 (2 NUMA nodes), 755 GiB RAM, PERC H730P in HBA mode, UEFI, iDRAC8 |
| SSDs | 6x 745 GiB SAS (3x WUSTR6480, 3x HUSMM3280), `rpool`: 3 mirrors, Proxmox root + VM/CT disks |
| HDDs | 4x 559 GiB 10K SAS, `garage`: raidz1 |
| NICs | `nic1` 1G (`f8:bc:12:1d:46:30`): trunk, untagged LAN + VLAN 20; `nic6` 10G (`3c:fd:fe:18:73:62`): VLAN 20 native |
| Guests | VM 200 `worker-07` (Talos), CT 210 `garage-01` (Garage S3) |

## After

| Disks | Use |
|---|---|
| 2 SSDs (`naa.5000cca0a670c818`, `naa.5000cca09c017658`) | Talos system disk: md RAID1 via `RAIDArrayConfig` `boot` |
| 4 SSDs | Pool `fast`: two mirrors (~1.41 TiB) |
| 4 HDDs | Pool `hdd` (the old `garage` pool, imported and renamed) |

Every mirror, the boot array included, pairs one WUSTR6480 with one HUSMM3280. Talos 1.14 cannot
replace a failed RAID member in place: a dead boot disk means `talosctl wipe md` and a reinstall,
which leaves the ZFS pools untouched.

| Dataset | Mountpoint | Consumer |
|---|---|---|
| `fast/extra` (quota 1T) | `/var/mnt/extra` | `openebs-hostpath-fast` (basePath `/var/mnt/extra/openebs/fast`) |
| `fast/runners` (quota 360G) | `/var/mnt/runners` | `openebs-hostpath-runners`: amd64 CI runners, bounded together so a burst stays off the TSDBs |
| `fast/garage-meta` | `/var/mnt/garage/meta` | Garage LMDB, in `meta/` |
| `hdd/media` | `/var/mnt/media` | `openebs-hostpath-media` (Immich library) |
| `hdd/garage-data` | `/var/mnt/garage/data` | Garage blocks, in `blocks/` |

`openebs-hostpath` enforces XFS project quotas, which cannot work on ZFS, so it has
`allowedTopologies` for every node except worker-07; the `-fast` and `-runners` classes only allow
worker-07. The `zfs` extension imports both pools at boot (`zpool import -fal`), `zfs_arc_max` caps
ARC at 64 GiB, and `system/zfs-scrub` scrubs both monthly.

Network: Talos DHCPs on nic6 (VLAN 20 native, `untagged: true` in `topf.yaml`); the UniFi reservation
and a `local_dns_record` (`worker-07.servers.internal`) pin `10.20.10.7`. nic1 is only used for PXE.

## Pull requests

| PR | Change |
|---|---|
| #2741 | r630 schematic with ZFS, RAID1 boot array, worker-07 node layer, UniFi reservation, netboot MAC |
| #2742 | `openebs-hostpath-fast` / `-runners`, claims switched, `openebs-hostpath` kept off worker-07 |
| #2747 | `-fast` / `-runners` pinned to worker-07 |
| #2748 | WWID boot selector, reservation import ID, `local_dns_record` |
| #2743 | Garage in the cluster, monitoring repointed |
| #2759 | Monthly ZFS scrub |
| #2760 | Proxmox and Garage-LXC leftovers removed |
| #2762 | `terraform-state` IAM role scoped to `unifi.tfstate` |

## What was done

1. **Backups.** Immich (670 GB) and Garage (metadata + blocks, from `@pre-talos-migration`
   snapshots) copied to PVCs on worker-ai-01's NVMe, then to the NAS (USB drive and `/volume1`);
   file counts and sizes verified. worker-07's `extra` volume copied to worker-ai-01 too.
2. **Pre-copy.** Live, from a zvol snapshot clone mounted read-only (`nouuid,norecovery`) on the
   host: the Immich zvol into a new `garage/media` dataset.
3. **PXE path.** Via the iDRAC's Redfish API: UEFI PXE rebound from integrated port 1 (no link) to
   port 3 (nic1), then a one-time `Pxe` boot override.
4. **Drain.** `debian-test` could not live-migrate (no other node has the same CPU model), so it was
   cold-restarted elsewhere. Final syncs of `extra` (after its consumers stopped) and `media`
   (after VM 200 shut down); Garage stopped and its metadata copied to the `garage` pool with
   `zfs send | recv`.
5. **Pool prep on Proxmox.** Garage's dataset renamed and its blocks moved into `blocks/`,
   ownership changed from the LXC's shifted uid to `1000`, mountpoints set under `/var/mnt`, the
   pool root set `canmount=off`, pool exported.
6. **Install.** PXE into maintenance mode, `talosctl wipe disk` on the two boot SSDs, `topf apply`:
   Talos built the RAID1 array and installed onto it.
7. **Pools.** `rpool` exported and its labels cleared, `fast` created, Garage metadata restored and
   checksum-verified, `garage` renamed to `hdd`.
8. **Claims.** ArgoCD's application controller and the Prometheus resource paused; the seven
   `extra` claims deleted (StatefulSets orphaned); #2742 merged; each new claim bound by a restore
   pod that tolerated the cordon and pulled its data from worker-ai-01; uncordoned.
9. **Garage.** #2743 merged. Same node ID (`0605350f4af4330e`), buckets intact, 0 block errors.
   The stale Cloudflare `s3.wibrow.dev` A record (from the LXC's DDNS role) was deleted so
   external-dns could publish the name. kopiur and CNPG backups resumed.
10. **Cleanup.** Old Immich zvol and rollback snapshots destroyed (`hdd` 79% → 40%); Proxmox and
    LXC config removed; Garage admin/metrics tokens rotated and split.

## What differed from the plan

- **No disk serials.** Behind the PERC in HBA mode Talos reports no serial for any disk, so a
  `disk.serial` selector matches nothing. Selectors use `disk.wwid`.
- **Schematics must be submitted.** topf computes schematic IDs locally; the Image Factory only
  serves one it has seen. The installer image 404'd until the schematic was POSTed to
  `https://factory.talos.dev/schematics`.
- **Kubelet serving cert denied.** kubelet-csr-approver resolves the node name. The PXE lease on
  nic1 had registered `worker-07` against a `192.168.0.x` address in UniFi, so every CSR was denied.
  Fixed with an explicit `local_dns_record` on the reservation.
- **UniFi destroys are not forgets.** The reservation resource uses `skip_forget_on_destroy`, so the
  old worker-07 client kept its fixed IP and blocked the new one (`DuplicateFixedIP`). The stale
  clients had to be forgotten through the API.
- **Pools imported everywhere.** `zpool import -fal` also imported the leftover `rpool`, mounting
  Proxmox's root dataset over `/` inside the extension's namespace. And the Multus daemon's
  `/hostroot` bind pins every mount under `/var/mnt`, so exporting any pool needs that node's Multus
  pod restarted first.
- **`openebs-hostpath-fast` initially had no topology.** herdr's claim, whose pod is not itself
  pinned, was provisioned on worker-02 until #2747 pinned both classes to worker-07.
- **ArgoCD syncs on every commit.** `selfHeal: false` does not stop an automated sync when `main`
  moves, which re-applied scaled-down workloads mid-cutover. Pausing the application controller was
  the reliable way.
- **CI runs on worker-07.** The self-hosted runners are pinned there, so Terraform and topf were
  applied locally while it was down.

## Still open

- The NVMe drives for the PCIe card (slot 1 or 2): either as a separate pool, or as the boot mirror
  so the two boot SSDs can join `fast` as a third mirror.
- SMART monitoring and pool-health alerts (the scrub Job only covers integrity).
- The NAS copies. The backup PVCs on worker-ai-01 were deleted on 2026-09-29; the NAS copies
  are the only off-node copy of the Immich library until it has an off-node backup of its own.
