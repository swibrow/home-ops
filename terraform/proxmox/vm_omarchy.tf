resource "proxmox_download_file" "omarchy" {
  content_type       = "iso"
  datastore_id       = var.iso_storage
  node_name          = var.omarchy.node
  url                = "https://iso.omarchy.org/omarchy-${var.omarchy.version}.iso"
  file_name          = "omarchy-${var.omarchy.version}.iso"
  checksum           = var.omarchy.iso_sha256
  checksum_algorithm = "sha256"
  upload_timeout     = 3600 # ~6GB

  # Install media only; Omarchy updates itself in-guest.
  overwrite = false
}

# Omarchy (Arch + Hyprland) desktop for gaming and development, streamed with
# Sunshine/Moonlight. Third holder of the RTX 3090 Ti next to vm_worker_ai_01.tf
# and vm_bazzite.tf, so it is off unless it is the one in use.
resource "proxmox_virtual_environment_vm" "omarchy" {
  name      = var.omarchy.name
  node_name = var.omarchy.node
  vm_id     = var.omarchy.vmid

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"

  started = false
  on_boot = false

  cpu {
    cores = var.omarchy.cores
    type  = "host"
  }

  memory {
    dedicated = var.omarchy.memory
    floating  = 0
  }

  # Secure Boot off: the NVIDIA kernel modules would otherwise need a MOK
  # enrolled from the guest console before the GPU works.
  efi_disk {
    datastore_id      = "nvme"
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = "nvme"
    interface    = "scsi0"
    size         = var.omarchy.disk
    iothread     = true
    cache        = "none"
    discard      = "on"
    ssd          = true
  }

  # rombar explicit, see vm_worker_ai_01.tf.
  hostpci {
    device  = "hostpci0"
    mapping = proxmox_hardware_mapping_pci.rtx3090ti.name
    pcie    = true
    rombar  = true
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = var.omarchy.mac
  }

  cdrom {
    file_id   = proxmox_download_file.omarchy.id
    interface = "ide2"
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0", "ide2"]

  lifecycle {
    ignore_changes = [
      cdrom,
      started, # AI/gaming mode is switched on the host; an apply must not undo it
      # Set by ansible (roles/proxmox gpu-exclusive.yaml): PVE only lets
      # root@pam with a password, not an API token, set a hookscript.
      hook_script_file_id,
    ]
  }
}
