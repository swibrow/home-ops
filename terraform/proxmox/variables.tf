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
  description = "Proxmox network bridge for the VM NIC"
  type        = string
  default     = "vmbr0"
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
    cores  = 30
    memory = 262141
    disk   = 1000
  }
}
