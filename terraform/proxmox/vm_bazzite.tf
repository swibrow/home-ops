resource "proxmox_download_file" "bazzite" {
  content_type       = "iso"
  datastore_id       = var.iso_storage
  node_name          = var.bazzite.node
  url                = "https://download.bazzite.gg/bazzite-nvidia-open-stable-amd64.iso"
  file_name          = "bazzite-nvidia-open-stable-amd64.iso"
  checksum           = "85e701c0f53189b0fa32797ffe8144202dcaa8db6c7692fd4677f615537b24b8"
  checksum_algorithm = "sha256"
  upload_timeout     = 3600 # ~8GB

  # The URL is a moving "stable" pointer. Only the install media lives here;
  # Bazzite updates itself in-guest, so a newer upstream ISO is not a reason to
  # re-download (and would no longer match the pinned checksum).
  overwrite = false
}

# Bazzite gaming VM streamed with Sunshine/Moonlight. Takes the RTX 3090 Ti from
# vm_worker_ai_01.tf, so it is off unless gaming mode is on.
resource "proxmox_virtual_environment_vm" "bazzite" {
  name      = var.bazzite.name
  node_name = var.bazzite.node
  vm_id     = var.bazzite.vmid

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"

  started = false
  on_boot = false

  # Installed by ansible (roles/proxmox, host_vars/proxmox-02.yaml). Starting
  # this VM shuts worker_ai down first; stopping it starts worker_ai again.
  hook_script_file_id = "local:snippets/gpu-exclusive.sh"

  cpu {
    cores = var.bazzite.cores
    type  = "host"
  }

  memory {
    dedicated = var.bazzite.memory
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
    size         = var.bazzite.disk
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
    mac_address = var.bazzite.mac
  }

  cdrom {
    file_id   = proxmox_download_file.bazzite.id
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
    ]
  }
}
