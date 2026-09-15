# The RTX 3090 Ti on proxmox-02, shared by vm_worker_ai_01.tf and vm_bazzite.tf.
# A cluster resource mapping rather than hostpci.id because the provider cannot
# set a raw PCI id with API-token auth (root password only).
#
# path without a function number maps every function of the card - the VGA
# controller (01:00.0) and its HDMI audio (01:00.1), which share IOMMU group 12
# and are both bound to vfio-pci on the host (ansible host_vars/proxmox-02.yaml).
resource "proxmox_hardware_mapping_pci" "rtx3090ti" {
  name    = "rtx3090ti"
  comment = "MSI RTX 3090 Ti on proxmox-02 - one VM at a time"

  map = [
    {
      node         = var.worker_ai.node
      path         = "0000:01:00"
      id           = "10de:2203"
      subsystem_id = "1462:5091"
      iommu_group  = 12
    },
  ]
}
