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
# "iot" is the one deliberate exception to adopt-only: its PD block is desired
# state, not adopted state. Matter/Thread needs routable IPv6 on VLAN 101.

resource "unifi_network" "default" {
  name    = "Default"
  purpose = "corporate"

  subnet       = "192.168.0.1/24"
  dhcp_enabled = true
  dhcp_start   = "192.168.0.6"
  dhcp_stop    = "192.168.0.190"
  domain_name  = "internal"

  # Prefix Delegation from the ISP WAN - the only network with IPv6 enabled.
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

  dhcp_v6_dns_auto           = false
  dhcp_v6_lease              = 0
  ipv6_ra_preferred_lifetime = 0
  ipv6_ra_valid_lifetime     = 0

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

  # PD sub-prefix from the same ISP delegation as Default - needed for the
  # Thread border router behind HA's Matter integration.
  #
  # pd_interface and pd_prefixid are what make this actually apply. Without
  # pd_interface the controller has no WAN to slice and rejects the whole PUT
  # with api.err.PdRequiresAssignedDhcpv6Wan, which is why this block silently
  # never took effect between 2026-08-25 and 2026-09-10. prefixid picks *which*
  # /64 out of the delegation: Default holds the first slice, so iot must not
  # also claim it or the two networks collide.
  #
  # pd_start/pd_stop are the host range inside that /64. Default only has one
  # because it was adopted from the controller; enabling PD fresh without it
  # is rejected with api.err.InvalidIpv6Addr (2026-09-13 and 2026-09-14 applies).
  # Same range as Default.
  ipv6_interface_type    = "pd"
  ipv6_pd_interface      = "wan"
  ipv6_pd_prefixid       = "1"
  ipv6_pd_start          = "::2"
  ipv6_pd_stop           = "::7d1"
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
  dhcp_start   = "10.20.0.46"
  dhcp_stop    = "10.20.255.254"
  domain_name  = "servers.internal"

  dhcp_v6_dns_auto           = false
  dhcp_v6_lease              = 0
  ipv6_ra_preferred_lifetime = 0
  ipv6_ra_valid_lifetime     = 0

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

  dhcp_v6_dns_auto           = false
  dhcp_v6_lease              = 0
  ipv6_ra_preferred_lifetime = 0
  ipv6_ra_valid_lifetime     = 0

  multicast_dns = true
}
