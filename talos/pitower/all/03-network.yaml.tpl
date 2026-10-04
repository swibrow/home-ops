# All cluster traffic rides VLAN 20; the API VIP (10.20.10.0) floats across
# the control planes. Per-node MACs come from node data in topf.yaml.
#
# Nodes flagged `untagged: true` in topf.yaml sit on a port that is already
# access-mode VLAN 20 (worker-07's 10G nic6), so they take DHCP on the parent instead
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
# The IPv6 node IP is the SLAAC address on VLAN 20 (UniFi PD slice 2). Most
# nodes also autoconfigure one on their untagged Default-LAN link (slice 0),
# which must not become the node IP.
---
apiVersion: v1alpha1
kind: KubeNodeConfig
nodeIP:
  validSubnets:
    - 10.20.0.0/16
    - 2a02:16a:2a0a:2::/64
# Dual-stack, IPv4 first so the existing ClusterIPs and clusterDNS keep their
# family. Nodes registered before IPv6 was added keep a single pod CIDR
# (spec.podCIDRs is immutable); they only get an IPv6 /64 by deleting the
# Node object and restarting kubelet.
---
apiVersion: v1alpha1
kind: KubeNetworkConfig
podSubnets:
  - 10.244.0.0/16
  - fd10:244::/56
serviceSubnets:
  - 10.96.0.0/12
  - fd10:96::/112
