# Garage S3 node, as an LXC container rather than a VM: Garage is a single
# static binary with no kernel requirements, so a full VM only adds a guest
# kernel and a virtual disk layer between it and the ZFS pool. The 500G data
# volume is a plain ZFS dataset the host can snapshot/replicate directly.
#
# Scope boundary is the same as the VMs here: this creates the container
# shell + data volume. Installing and configuring Garage itself belongs in
# ansible/ (see README.md).

resource "proxmox_download_file" "debian_lxc_template" {
  content_type = "vztmpl"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node
  url          = var.lxc_template_url
}

resource "proxmox_virtual_environment_container" "garage" {
  node_name = var.proxmox_node
  vm_id     = var.garage.vmid

  description   = "Garage S3 node - managed by terraform/proxmox"
  unprivileged  = true
  start_on_boot = true
  started       = true

  operating_system {
    template_file_id = proxmox_download_file.debian_lxc_template.id
    type             = "debian"
  }

  cpu {
    cores = var.garage.cores
  }

  memory {
    dedicated = var.garage.memory
    swap      = 0
  }

  disk {
    datastore_id = var.disk_storage
    size         = var.garage.root_disk
  }

  # Garage's metadata (LMDB) and data blocks both live under /var/lib/garage.
  # Kept off the rootfs so the container can be rebuilt without touching data,
  # and so the dataset can be snapshotted/replicated on its own.
  mount_point {
    volume = var.disk_storage
    size   = "${var.garage.data_disk}G"
    path   = "/var/lib/garage"
    backup = false
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
    # No vlan_id, same reason as the VMs: vmbr0 already carries VLAN20 as a
    # flat tag on the host side (nic1.20 -> vmbr0).
  }

  initialization {
    hostname = var.garage.name

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = local.ssh_public_keys
    }
  }

  # Terraform hands off after first boot; ansible manages the guest from there.
  lifecycle {
    ignore_changes = [
      initialization[0].user_account, # rotating keys in-guest shouldn't recreate the CT
    ]
  }
}
