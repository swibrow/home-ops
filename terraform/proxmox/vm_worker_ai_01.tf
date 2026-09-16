resource "proxmox_download_file" "talos_nvidia_vm" {
  content_type = "iso"
  datastore_id = var.iso_storage
  node_name    = var.worker_ai.node
  url          = "https://factory.talos.dev/image/${var.worker_ai.talos_schematic_id}/${var.worker_ai.talos_version}/metal-amd64.iso"
  file_name    = "talos-${var.worker_ai.talos_version}-nvidia-vm-amd64.iso"
}

# Talos GPU worker. Gives up the RTX 3090 Ti whenever vm_bazzite.tf runs: the two
# VMs share one PCI mapping and must never be started together.
resource "proxmox_virtual_environment_vm" "worker_ai" {
  name      = var.worker_ai.name
  node_name = var.worker_ai.node
  vm_id     = var.worker_ai.vmid

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"

  started = true
  on_boot = true

  # See vm_bazzite.tf. Refuses to start while bazzite holds the GPU.
  hook_script_file_id = "local:snippets/gpu-exclusive.sh"

  agent {
    enabled = true
    timeout = "30s"
  }

  cpu {
    cores = var.worker_ai.cores
    type  = "host"
  }

  # PCI passthrough pins all guest RAM, so no ballooning.
  memory {
    dedicated = var.worker_ai.memory
    floating  = 0
  }

  efi_disk {
    datastore_id = "local-lvm"
    file_format  = "raw"
  }

  # System disk on the Kingston (local-lvm): Talos, EPHEMERAL, container images.
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.worker_ai.disk
    iothread     = true
    cache        = "none"
    discard      = "on"
    ssd          = true
  }

  # Talos user volume `models` (talos/pitower/node/worker-ai-01/02-models.yaml),
  # backing openebs-hostpath-models, on the Samsung 9100 Pro `nvme` pool. Its
  # size is what the volume's size-band selector keys on.
  #
  # Append new disks after this one - never reorder. terraform diffs `disk` by
  # position, see the note in vm_worker_07.tf.
  disk {
    datastore_id = "nvme"
    interface    = "scsi1"
    size         = var.worker_ai.models_disk
    iothread     = true
    cache        = "none"
    discard      = "on"
    ssd          = true
  }

  # rombar must be explicit: left unset the provider writes rombar=0, which hides
  # the card's option ROM from the guest firmware.
  hostpci {
    device  = "hostpci0"
    mapping = proxmox_hardware_mapping_pci.rtx3090ti.name
    pcie    = true
    rombar  = true
  }

  # vmbr0 on proxmox-02 is nic0.20, so the guest sees VLAN 20 untagged
  # (`untagged: true` in topf.yaml). The pinned MAC is what the worker-ai-01
  # reservation in terraform/unifi hands 10.20.10.11 to.
  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = var.worker_ai.mac
  }

  cdrom {
    file_id   = proxmox_download_file.talos_nvidia_vm.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0", "ide2"]

  lifecycle {
    ignore_changes = [
      cdrom,   # installer detaches its own boot media after install
      started, # AI/gaming mode is switched on the host; an apply must not undo it
    ]
  }
}
