# All cluster traffic rides VLAN 20; the API VIP (10.20.10.0) floats across
# the control planes. Per-node MACs come from node data in topf.yaml.
#
# Nodes flagged `untagged: true` in topf.yaml sit on a port that is already
# access-mode VLAN 20 (Proxmox vNIC), so they take DHCP on the parent instead
# of building a subinterface; a vlans: entry there would double-tag and never
# get a lease. The bare-metal nodes' ports trunk VLAN 20 tagged and carry a
# different untagged segment, so they keep the subinterface.
#
# machine.network.interfaces is deprecated in 1.14 but still accepted, and has
# no single-document replacement (it would split into LinkConfig, VLANConfig,
# DHCPv4Config and Layer2VIPConfig). Left as-is on purpose.
machine:
  network:
    interfaces:
      - deviceSelector:
          physical: true
          hardwareAddr: {{ .Node.Data.mac }}
        {{- /* index, not .Node.Data.untagged: topf renders with missingkey=error */}}
        {{- if index .Node.Data "untagged" }}
        dhcp: true
        {{- else }}
        vlans:
          - vlanId: 20
            dhcp: true
            {{- if eq .Node.Role "control-plane" }}
            vip:
              ip: 10.20.10.0
            {{- end }}
        {{- end }}
---
apiVersion: v1alpha1
kind: KubeNodeConfig
nodeIP:
  validSubnets:
    - 10.20.0.0/16
