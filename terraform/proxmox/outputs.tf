output "talos_worker_vm_id" {
  description = "Proxmox VMID of the Talos worker VM"
  value       = proxmox_virtual_environment_vm.talos_worker.vm_id
}

output "talos_worker_mac_address" {
  description = "NIC MAC address - pin this in talos/pitower/topf.yaml's node entry once the VM boots"
  value       = proxmox_virtual_environment_vm.talos_worker.network_device[0].mac_address
}
