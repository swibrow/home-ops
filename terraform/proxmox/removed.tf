# proxmox-02 was wiped and reinstalled as bare-metal Talos (worker-ai-01), so its
# VMs and ISOs are gone with it. Forget them instead of destroying: the API calls
# would go to a node that no longer exists. Delete this file after it applies.
removed {
  from = proxmox_virtual_environment_vm.worker_ai
  lifecycle {
    destroy = false
  }
}

removed {
  from = proxmox_virtual_environment_vm.bazzite
  lifecycle {
    destroy = false
  }
}

removed {
  from = proxmox_virtual_environment_vm.omarchy
  lifecycle {
    destroy = false
  }
}

removed {
  from = proxmox_download_file.talos_nvidia_vm
  lifecycle {
    destroy = false
  }
}

removed {
  from = proxmox_download_file.bazzite
  lifecycle {
    destroy = false
  }
}

removed {
  from = proxmox_download_file.omarchy
  lifecycle {
    destroy = false
  }
}
