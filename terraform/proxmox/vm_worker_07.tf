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
    cores = var.talos_worker.cores
    type  = "host"
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
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
    # No vlan_id: vmbr0 itself carries VLAN20 as a flat tag on the host side
    # (nic1.20 -> vmbr0), so guest traffic is already on VLAN20 untagged from
    # the bridge's perspective. Tagging here too would double-tag.
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
