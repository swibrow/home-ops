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

  # Debian 13 ships systemd 257, which wants user namespaces inside the guest
  # (pct warns "Systemd 257 detected. You may need to enable nesting").
  features {
    nesting = true
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

  # Garage's METADATA tier. The LMDB engine does small random writes, the worst
  # possible pattern for spinning rust, so it stays on rpool (six enterprise SAS
  # SSDs). It is small - ~255M against this 500G dataset. Kept off the rootfs so
  # the container can be rebuilt without touching it, and so the dataset can be
  # snapshotted on its own.
  mount_point {
    volume = var.disk_storage
    size   = "${var.garage.data_disk}G"
    path   = "/var/lib/garage"
    backup = false
  }

  # Garage's DATA tier: S3 object blocks, on the `garage` raidz1 over four 10K
  # SAS spinners. Large sequential IO is what those disks are good at, and it is
  # where the capacity is (1.53T pool). Splitting the tiers is deliberate -
  # putting LMDB here would make S3 writes crawl, and putting objects on rpool
  # would burn SSD on bulk storage.
  #
  # APPEND ONLY. `mount_point` is a list and terraform diffs it by position, the
  # same trap documented at length in vm_worker_07.tf - inserting a block ahead
  # of an existing one makes terraform read it as "this mount changed volume"
  # and rewrite the wrong dataset. This one was added 2026-08-13 after the data
  # was already copied and verified, so terraform adopts rather than creates.
  mount_point {
    volume = "garage"
    size   = "1000G"
    path   = "/data"
    backup = false
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
    # No vlan_id, same reason as the VMs: the bridge already carries VLAN20
    # as a flat tag on the host side (nic6.20 -> vmbr2).
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
