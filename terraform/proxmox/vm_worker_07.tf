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
    # rpool is 8x 600GB 10K SAS spinning disks (4 mirror vdevs, no SLOG), so with
    # the default cache=none every guest sync write waits on a seek - measured
    # 14.65ms avg write latency here vs 0.4-0.6ms on the NVMe control planes, at
    # the same ~350 write IOPS. writeback lets the host absorb writes in its ARC
    # (128GiB, on 755GiB of RAM) instead. The power-loss window this opens is
    # covered by the UPS + dual PSU.
    #
    # writeback alone only got this to ~11ms; the rest of the fix is sync=disabled
    # on the backing zvol, which is NOT settable from here (Proxmox exposes no
    # per-VM knob - it is a host-side ZFS dataset property). It lives in the
    # ansible proxmox role as proxmox_zfs_volume_properties, and that is where the
    # measurements and the durability trade-off are written up.
    #
    # If this disk is ever recreated, the new zvol defaults back to sync=standard
    # and write latency silently returns to ~11ms. Rerun the ansible proxmox role
    # after any recreate.
    cache = "writeback"
  }

  disk {
    # Scratch disk on the single 500GB SATA SSD in bay 8 (zpool `scratch`,
    # Proxmox storage `scratch`). No redundancy and no PLP - holds only
    # rebuildable write-heavy data (TSDB PVCs) to keep their WAL churn off the
    # spinning rpool. cache=none: the SSD doesn't need the host page cache and
    # writeback would just burn ARC-adjacent RAM.
    datastore_id = "scratch"
    interface    = "scsi1"
    size         = 450
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # scsi2 (GitHub-runner scratch on the `runners` zpool) is intentionally absent:
  # the 4x Samsung 830 stripe is being replaced by 2x 500GB SSDs, so the pool and
  # its zvol are destroyed. Runner PVCs are parked on openebs-hostpath-ssd
  # meanwhile. Restore this block, the Talos UserVolumeConfig at
  # talos/pitower/node/worker-07/03-runners.yaml and its kubelet extraMount
  # together - the Talos side selects the disk by size band.

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
