# Existing networks, adopted from the live controller via the import blocks in
# imports.tf rather than hand-typed. Values mirror what the controller reports
# so the adopting plan is a no-op; most other fields are Optional+Computed and
# safe to leave unset - the provider preserves whatever the controller has.
#
# The ipv6_* / dhcp_v6_* blocks below are not aspirational config: the provider
# schema defaults them to RFC lifetimes (86400/14400) and dhcp_v6_dns_auto=true,
# while this controller stores 0/false. Left unset, adoption would write those
# defaults back on every network. Inert on the four with ipv6_interface_type
# "none", but "Default" carries the ISP prefix delegation, where the same drift
# would have flipped ipv6_ra_enable true -> null and dropped router
# advertisements on the main LAN. Pin them to the live values instead.

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

  dhcp_v6_dns_auto           = false
  dhcp_v6_lease              = 0
  ipv6_ra_preferred_lifetime = 0
  ipv6_ra_valid_lifetime     = 0

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
  domain_name  = "servers.local"

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
