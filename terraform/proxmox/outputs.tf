output "talos_worker_vm_id" {
  description = "Proxmox VMID of the Talos worker VM"
  value       = proxmox_virtual_environment_vm.talos_worker.vm_id
}

output "talos_worker_mac_address" {
  description = "NIC MAC address - pin this in talos/pitower/topf.yaml's node entry once the VM boots"
  value       = proxmox_virtual_environment_vm.talos_worker.network_device[0].mac_address
}

output "garage_container_id" {
  description = "Proxmox VMID of the Garage S3 LXC container"
  value       = proxmox_virtual_environment_container.garage.vm_id
}

output "garage_mac_address" {
  description = "eth0 MAC address - pin the DHCP lease to it with a UniFi reservation"
  value       = proxmox_virtual_environment_container.garage.network_interface[0].mac_address
}
