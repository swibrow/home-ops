# Existing networks, imported from the live controller (see README.md's
# "Importing existing config" section) rather than hand-typed. Values mirror
# what the controller currently reports so import produces a clean (no-op) plan;
# most other fields are Optional+Computed and safe to leave unset - the provider
# preserves whatever the controller already has for them.

resource "unifi_network" "default" {
  name    = "Default"
  purpose = "corporate"

  subnet       = "192.168.0.1/24"
  dhcp_enabled = true
  dhcp_start   = "192.168.0.6"
  dhcp_stop    = "192.168.0.190"
  domain_name  = "internal"

  # Prefix Delegation from the ISP WAN - the only network with IPv6 enabled.
  ipv6_interface_type = "pd"

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

  multicast_dns = true
}
