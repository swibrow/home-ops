# Static address on the parent (untagged) interface so the netboot pod
# (hostNetwork proxyDHCP, kubernetes/apps/pitower/networking/netboot) can
# serve PXE clients on the untagged LAN, where Talos maintenance mode comes
# up. topf concatenates this with all/03-network.yaml.tpl's entry for the
# same NIC (VLAN 20 stays there). No gateway on purpose - the default route
# stays on VLAN 20.
machine:
  network:
    interfaces:
    - deviceSelector:
        physical: true
        hardwareAddr: {{ .Node.Data.mac }}
      dhcp: false
      addresses:
        - 192.168.0.249/24
