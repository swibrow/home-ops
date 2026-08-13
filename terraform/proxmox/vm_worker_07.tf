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
    # writeback dates from when rpool was four 10K SAS spinners with no SLOG:
    # cache=none made every guest sync write wait on a seek (14.65ms here vs
    # 0.4-0.6ms on the NVMe control planes at the same ~350 write IOPS), so the
    # host absorbed them in ARC instead. Its companion hack, sync=disabled on
    # the backing zvol, was removed on 2026-08-13 along with the ansible
    # `proxmox_zfs_volume_properties` loop that set it.
    #
    # rpool is now six enterprise SAS SSDs with power-loss protection, so the
    # premise is gone: a real fsync is cheap. writeback is kept for now only
    # because changing cache mode needs a full VM stop+start (it is fixed at
    # QEMU process start - `qm set` merely queues it, see `qm pending 200`),
    # and because it still helps bulk/compaction throughput. It is worth
    # revisiting: on PLP flash it mostly buys RAM churn while reopening a
    # host-crash window the drives were bought to close.
    cache = "writeback"
  }

  disk {
    # TSDB scratch: prometheus, victoria-metrics, victoria-logs and tempo, via
    # the openebs-hostpath-ssd class on Talos user volume `scratch`.
    #
    # Was the single 500GB SATA SSD in bay 8 (zpool `scratch`), which existed
    # only to keep WAL churn off a spinning rpool. rpool is six enterprise SAS
    # SSDs since 2026-08-13, so the tier has no reason to exist and the bay is
    # wanted for the garage raidz1. cache=none is kept: the host page cache buys
    # nothing here and writeback would just burn ARC-adjacent RAM.
    #
    # Size must stay in the 400-500GiB band - the Talos UserVolumeConfig picks
    # this disk by size, not by name. See talos/pitower/node/worker-07/.
    datastore_id = var.disk_storage
    interface    = "scsi1"
    size         = 450
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  disk {
    # GitHub-runner scratch: per-job work dirs and dind's /var/lib/docker,
    # nothing that must survive a power cut. Was the 500GB Samsung 850 EVO in
    # bay 9 (zpool `runners`, sync=disabled on consumer TLC); folded onto rpool
    # 2026-08-13 to free the bay for the garage raidz1.
    #
    # 350GiB is deliberate, not spare-capacity rounding: the Talos
    # UserVolumeConfig picks disks by SIZE BAND, and 400-500GiB already belongs
    # to scratch (scsi1). Growing this past 400GiB means widening both
    # selectors in the same change. See talos/pitower/node/worker-07/.
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
    interface    = "scsi2"
    size         = 350
    iothread     = true
    discard      = "on"
    ssd          = true
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
