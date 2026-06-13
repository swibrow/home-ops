# All cluster traffic rides VLAN 20; the API VIP (10.20.10.0) floats across
# the control planes. Per-node MACs come from node data in topf.yaml.
machine:
  kubelet:
    nodeIP:
      validSubnets:
        - 10.20.0.0/16
  network:
    interfaces:
      - deviceSelector:
          physical: true
          hardwareAddr: {{ .Node.Data.mac }}
        vlans:
          - vlanId: 20
            dhcp: true
            {{- if eq .Node.Role "control-plane" }}
            vip:
              ip: 10.20.10.0
            {{- end }}
