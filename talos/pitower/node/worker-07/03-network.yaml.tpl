# Proxmox VM: the hypervisor's vmbr0 already places this vNIC on VLAN20
# untagged (flat access mode, not a trunk) - unlike the bare-metal nodes'
# physical trunk ports, this NIC never sees tagged frames, so no vlans:
# subinterface here (all/03-network.yaml.tpl's would double-tag on this node).
machine:
  network:
    interfaces:
      - deviceSelector:
          physical: true
          hardwareAddr: {{ .Node.Data.mac }}
        dhcp: true
