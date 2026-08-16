resource "proxmox_download_file" "talos" {
  content_type = "iso"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node
  url          = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/metal-amd64.iso"
  file_name    = "talos-${var.talos_version}-proxmox-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  name      = var.talos_worker.name
  node_name = var.proxmox_node
  vm_id     = var.talos_worker.vmid

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"

  started = true
  on_boot = true

  agent {
    enabled = true
    # Default timeout is 15m - Talos won't have the agent running until it's
    # actually installed and booted (not during the ISO/maintenance-mode
    # phase), so refresh/read would otherwise block for the full 15m every
    # time against a VM that isn't there yet.
    timeout = "30s"
  }

  cpu {
    # 2x16 mirrors the host's two NUMA nodes (2x E5-2687W v4, 12c/24t each);
    # numa=true is required so the ~364GiB of guest RAM splits across both host
    # nodes instead of presenting as one flat remote-heavy node. Memory must
    # stay divisible by the socket count or the VM refuses to start.
    cores   = var.talos_worker.cores
    sockets = 2
    numa    = true
    type    = "host"
  }

  memory {
    dedicated = var.talos_worker.memory
    floating  = 0 # no ballooning - avoids confusing kubelet memory reporting
  }

  efi_disk {
    datastore_id = var.disk_storage
    file_format  = "raw"
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = var.talos_worker.disk
    iothread     = true
    # cache=none, matching scsi1/scsi2. writeback dated from when rpool was
    # four 10K SAS spinners with no SLOG: cache=none made every guest sync
    # write wait on a seek (14.65ms here vs 0.4-0.6ms on the NVMe control
    # planes at the same ~350 write IOPS), so the host absorbed them in ARC
    # instead. Its companion hack, sync=disabled on the backing zvol, was
    # removed on 2026-08-13. rpool is six enterprise SAS SSDs with power-loss
    # protection since then, so a real fsync is cheap and writeback only bought
    # RAM churn plus a host-crash window the drives were bought to close.
    #
    # discard=on + ssd=1: without discard the guest's freed blocks never
    # returned to ZFS, which is how this zvol reached 495G of a 1000G disk with
    # ~341G of it containerd image cache kubelet never GCs.
    #
    # All three take effect at QEMU process start, so changing them needs a
    # full VM stop+start - `qm set` merely queues them, see `qm pending 200`.
    cache   = "none"
    discard = "on"
    ssd     = true
  }

  disk {
    # Consolidated data volume: Talos user volume `extra`, mounted /var/mnt/extra,
    # backing the cluster-wide openebs-hostpath class. This is the ONLY non-system
    # disk - every worker-07 PVC lives here.
    #
    # Replaced scsi1 (`scratch`, TSDBs) and scsi2 (`runners`), removed 2026-08-14.
    # Those existed to keep TSDB WAL churn and runner bursts on separate spindles,
    # which stopped meaning anything on 2026-08-13 when all three became zvols on
    # the same SAS SSD rpool. Runner bursts are now held off the TSDBs by XFS
    # project quotas (UserVolumeConfig filesystem.projectQuotaSupport), which is a
    # stronger guarantee than separate disks gave: a runaway job fills its own
    # claim and stops.
    #
    # 800G covers the worst case with ~23% headroom: 100Gi of app PVCs, 190Gi of
    # TSDBs, and a 360Gi full runner burst (6 x 60Gi, capped by ARC maxRunners).
    #
    # No size band needed - the volume selector is `!system_disk`, so this is
    # simply "the disk that is not scsi0".
    #
    # DO NOT REORDER THE DISK BLOCKS. `disk` is a list and terraform diffs its
    # elements by position in this file, not by interface number. On 2026-08-11
    # a block inserted in scsi-slot order shifted every later element by one;
    # terraform read that as "this index changed datastore" and planned an
    # in-place rewrite of the disk holding the Immich photo library, plus a
    # replacement. It auto-applied, and only missed destroying the library
    # because Proxmox errored on the new zvol's device link partway through -
    # leaving a phantom disk in state and a blanked path_in_datastore to repair
    # by hand. Append new disks; never insert.
    datastore_id = var.disk_storage
    interface    = "scsi3"
    size         = 800
    iothread     = true
    cache        = "none"
    discard      = "on"
    ssd          = true
  }

  disk {
    # The Immich photo library: Talos user volume `media`, mounted /var/mnt/media,
    # backing openebs-hostpath-media. Appended 2026-08-16 because the Synology is
    # failing and /data had to come off NFS.
    #
    # This is the ONE disk that does not live on rpool. It is on the `garage`
    # raidz1 (4x 600GB Toshiba 10K SAS, bays 6-9) because that is the only
    # redundant bulk storage in the chassis, and because photos are the only
    # thing here that is not rebuildable from an image pull. It is also the only
    # disk backed by spinners, hence ssd = false - the guest should schedule it
    # as rotational.
    #
    # The `garage` storage needs `blocksize 128k` set BEFORE this zvol is cut,
    # or parity padding on a 4-wide raidz1 eats a large fraction of the pool.
    # volblocksize is fixed at creation; a wrong one is only fixable by
    # recreating the zvol. See ansible/roles/proxmox/defaults/main.yaml.
    #
    # 1200GiB restores the historical `media` size band (1100-1300GiB) that the
    # Talos volume selector keys on. It is thin, and it overcommits the pool -
    # 1200GiB here plus garage's 1000G subvol refquota against 1.53T usable. Only
    # ~62G of photos exist today so this is fine now, but a real 1TB import
    # cannot coexist with garage's advertised 900G. Cut garage's layout capacity
    # before importing at scale, and watch the pool, not the guest filesystem: if
    # the pool fills, the zvol takes IO errors and xfs shuts down.
    #
    # DO NOT REORDER THE DISK BLOCKS - see the note on scsi3 above. Appended
    # last on purpose; interface order is not file order.
    datastore_id = "garage"
    interface    = "scsi4"
    size         = 1200
    iothread     = true
    cache        = "none"
    discard      = "on"
    ssd          = false
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
    # No vlan_id: the bridge itself carries VLAN20 as a flat tag on the host
    # side (nic6.20 -> vmbr2), so guest traffic is already on VLAN20 untagged
    # from the bridge's perspective. Tagging here too would double-tag.
  }

  cdrom {
    file_id = proxmox_download_file.talos.id
    # interface defaults to ide3, which the q35 machine type doesn't support
    # (only ide0/ide2) - explicit ide2 here to match boot_order below.
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0", "ide2"]

  # Talos boots into maintenance mode from the ISO; a human (or topf) runs
  # `talosctl apply-config` against its DHCP address next - same handoff as
  # the bare-metal nodes in talos/pitower/node/. Terraform's job stops at
  # the VM shell + install media.
  lifecycle {
    ignore_changes = [
      cdrom, # installer detaches its own boot media after install
    ]
  }
}
