# Existing networks, adopted from the live controller via the import blocks in
# imports.tf rather than hand-typed. Values mirror what the controller reports
# so the adopting plan is a no-op; most other fields are Optional+Computed and
# safe to leave unset - the provider preserves whatever the controller has.
#
# The ipv6_* / dhcp_v6_* blocks below are not aspirational config: the provider
# schema defaults them to RFC lifetimes (86400/14400) and dhcp_v6_dns_auto=true,
# while this controller stores 0/false. Left unset, adoption would write those
# defaults back on every network. Inert on the three with ipv6_interface_type
# "none", but "Default" carries a slice of the ISP prefix delegation, where the
# same drift would have flipped ipv6_ra_enable true -> null and dropped router
# advertisements. Pin them to the live values instead.
#
# Every network except "Default" is a deliberate exception to adopt-only:
# their IPv6 blocks are desired state, not adopted state. Matter/Thread needs
# routable IPv6 on VLAN 101, the pitower nodes take their IPv6 addresses
# (SLAAC) from VLAN 20, and home/management clients reach the cluster's
# LoadBalancer AAAA records over it.
#
# Those four use static /64s carved from the Init7 /56, not PD: the gateway
# ignores ipv6_pd_prefixid and reshuffles PD slices whenever the WAN
# reconnects (2026-10-23, servers moved :2:: -> :3:: and the IPv6 BGP session
# to Cilium died with it). "Default" stays on PD because the /56 is only
# routed to us while the gateway holds a delegation lease; it takes slice 0,
# which none of the static networks use.

resource "unifi_network" "default" {
  name    = "Default"
  purpose = "corporate"

  subnet       = "192.168.0.1/24"
  dhcp_enabled = true
  dhcp_start   = "192.168.0.6"
  dhcp_stop    = "192.168.0.190"
  domain_name  = "internal"

  # Prefix Delegation from the ISP WAN, first slice (no prefixid).
  ipv6_interface_type    = "pd"
  ipv6_ra_enable         = true
  ipv6_ra_valid_lifetime = 0

  multicast_dns = true
}

resource "unifi_network" "home" {
  name    = "home"
  purpose = "corporate"

  subnet       = "10.10.0.1/16"
  vlan_id      = 10
  dhcp_enabled = true
  dhcp_start   = "10.10.0.46"
  dhcp_stop    = "10.10.255.254"

  ipv6_interface_type    = "static"
  ipv6_static_subnet     = "2a02:16a:2a0a:3::1/64"
  ipv6_ra_enable         = true
  ipv6_ra_valid_lifetime = 0

  dhcp_v6_dns_auto           = false
  dhcp_v6_lease              = 0
  ipv6_ra_preferred_lifetime = 0

  multicast_dns = true
}

resource "unifi_network" "iot" {
  name    = "iot"
  purpose = "corporate"

  subnet       = "10.101.0.1/16"
  vlan_id      = 101
  dhcp_enabled = true
  dhcp_start   = "10.101.0.46"
  dhcp_stop    = "10.101.255.254"
  domain_name  = "iot"

  # Needed for the Thread border router behind HA's Matter integration.
  ipv6_interface_type    = "static"
  ipv6_static_subnet     = "2a02:16a:2a0a:1::1/64"
  ipv6_ra_enable         = true
  ipv6_ra_valid_lifetime = 0

  multicast_dns = true
}

resource "unifi_network" "servers" {
  name    = "servers"
  purpose = "corporate"

  subnet       = "10.20.0.1/16"
  vlan_id      = 20
  dhcp_enabled = true
  # 10.20.0.0-10.20.199.255 is static: nodes and API VIP (10.20.10.0-11),
  # Cilium LB pool (10.20.10.128-255), Multus pod IPs, and the reservations in
  # reservations.tf, which the controller serves outside the range.
  dhcp_start  = "10.20.200.1"
  dhcp_stop   = "10.20.255.254"
  domain_name = "servers.internal"

  # Talos (kubelet nodeIP.validSubnets), kubelet-csr-approver, the Cilium
  # ucg-v6 peer and the BGP listen range in frr-bgp.conf all name this /64.
  ipv6_interface_type    = "static"
  ipv6_static_subnet     = "2a02:16a:2a0a:2::1/64"
  ipv6_ra_enable         = true
  ipv6_ra_valid_lifetime = 0

  dhcp_v6_dns_auto           = false
  dhcp_v6_lease              = 0
  ipv6_ra_preferred_lifetime = 0

  multicast_dns = true
}

resource "unifi_network" "management" {
  name    = "management"
  purpose = "corporate"

  subnet       = "10.50.0.1/24"
  vlan_id      = 50
  dhcp_enabled = true
  dhcp_start   = "10.50.0.6"
  dhcp_stop    = "10.50.0.254"

  ipv6_interface_type    = "static"
  ipv6_static_subnet     = "2a02:16a:2a0a:4::1/64"
  ipv6_ra_enable         = true
  ipv6_ra_valid_lifetime = 0

  dhcp_v6_dns_auto           = false
  dhcp_v6_lease              = 0
  ipv6_ra_preferred_lifetime = 0

  multicast_dns = true
}
