variable "proxmox_node" {
  description = "Proxmox node name to place the VM on"
  type        = string
  default     = "proxmox-01"
}

variable "iso_storage" {
  description = "Proxmox storage ID that holds ISO images - confirm this matches proxmox-01's actual storage config"
  type        = string
  default     = "local"
}

variable "disk_storage" {
  description = "Proxmox storage ID for the VM disk (and EFI disk) - the ZFS RAID10 pool (rpool), exposed as the local-zfs storage ID"
  type        = string
  default     = "local-zfs"
}

variable "network_bridge" {
  description = "Proxmox network bridge for the VM NIC - dedicated 10G guest bridge (vmbr2, tagged VLAN20 same as vmbr0), not the 1G host-management vmbr0"
  type        = string
  default     = "vmbr2"
}

variable "talos_version" {
  description = "Talos version to install - keep in sync with talos/pitower/topf.yaml's talosVersion"
  type        = string
  default     = "1.13.3"
}

variable "talos_schematic_id" {
  description = "Talos factory schematic ID for this VM - resolved from talos/pitower/extensions/proxmox.yaml (qemu-guest-agent only, no bare-metal microcode/GPU extensions)"
  type        = string
  default     = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
}

variable "talos_worker" {
  description = "Talos worker VM sizing - adjust to taste before applying"
  type = object({
    vmid   = number
    name   = string
    cores  = number
    memory = number # MiB
    disk   = number # GiB
  })
  default = {
    vmid   = 200
    name   = "pitower-worker-07"
    cores  = 16
    memory = 372736
    disk   = 1000
  }
}

variable "worker_ai" {
  description = "Talos GPU worker VM on proxmox-02. 14 of the 9700X's 16 threads and 48GiB of its ~59GiB, leaving room for the host and the nvme pool's ARC (capped at 6GiB). models_disk must stay inside the 500-700GiB band of the `models` user volume selector"
  type = object({
    node               = string
    vmid               = number
    name               = string
    cores              = number
    memory             = number # MiB
    disk               = number # GiB, local-lvm
    models_disk        = number # GiB, nvme
    mac                = string
    talos_version      = string
    talos_schematic_id = string
  })
  default = {
    node               = "proxmox-02"
    vmid               = 300
    name               = "pitower-worker-ai-01"
    cores              = 14
    memory             = 49152
    disk               = 250
    models_disk        = 600
    mac                = "bc:24:11:a1:00:11"
    talos_version      = "1.14.0"                                                           # topf.yaml talosVersion
    talos_schematic_id = "6511add25855b7b836413feab8ccc84516219816d7988bc162b12b6ee9158ead" # extensions/nvidia-vm.yaml
  }
}

variable "bazzite" {
  description = "Bazzite gaming VM on proxmox-02. Only runs while worker_ai is stopped, so it can take the same CPU threads"
  type = object({
    node   = string
    vmid   = number
    name   = string
    cores  = number
    memory = number # MiB
    disk   = number # GiB, nvme
    mac    = string
  })
  default = {
    node   = "proxmox-02"
    vmid   = 301
    name   = "bazzite"
    cores  = 14
    memory = 32768
    disk   = 1000
    mac    = "bc:24:11:a1:00:21"
  }
}

variable "lxc_template_url" {
  description = "Debian LXC template to base containers on - verify the exact filename exists with `pveam available --section system` on the host before applying"
  type        = string
  default     = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "ssh_public_keys" {
  description = "SSH public keys injected into container root accounts. Defaults to the operator's local ~/.ssh/id_ed25519.pub"
  type        = list(string)
  default     = null
}

variable "garage" {
  description = "Garage S3 LXC sizing. data_disk is the /var/lib/garage mount point (metadata + blocks); root_disk is just the Debian rootfs"
  type = object({
    vmid      = number
    name      = string
    cores     = number
    memory    = number # MiB
    root_disk = number # GiB
    data_disk = number # GiB
  })
  default = {
    vmid      = 210
    name      = "garage-01"
    cores     = 4
    memory    = 4096
    root_disk = 16
    data_disk = 500
  }
}

locals {
  ssh_public_keys = coalesce(
    var.ssh_public_keys,
    compact([trimspace(try(file(pathexpand("~/.ssh/id_ed25519.pub")), ""))]),
  )
}
