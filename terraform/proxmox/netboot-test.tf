# Throwaway PXE test VM for the netboot server: empty disk + NIC on the
# untagged-LAN bridge (vmbr1), so firmware falls through to network boot -
# the same path a wiped bare-metal node takes. The MAC is pinned and mapped
# in the netboot menu (kubernetes/apps/pitower/networking/netboot) to default
# to the proxmox Talos schematic. Destroy after testing.
resource "proxmox_virtual_environment_vm" "netboot_test" {
  name      = "netboot-test"
  node_name = var.proxmox_node
  vm_id     = 201

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"

  started = true
  on_boot = false

  agent {
    enabled = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
    floating  = 0
  }

  efi_disk {
    datastore_id = var.disk_storage
    file_format  = "raw"
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = 10
    iothread     = true
  }

  network_device {
    bridge      = "vmbr1"
    model       = "virtio"
    mac_address = "bc:24:11:0e:b0:07"
  }

  operating_system {
    type = "l26"
  }

  boot_order = ["scsi0", "net0"]
}
