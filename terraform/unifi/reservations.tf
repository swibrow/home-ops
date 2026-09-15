# Extra/ad-hoc reservations on top of local.known_reservations below - variable
# defaults can't reference resources (e.g. unifi_network.servers.id), so the
# codified set lives in a local instead. See README.md for how to source a
# device's MAC address.
variable "reservations" {
  description = "Additional DHCP reservations to manage, keyed by client name (shown in the UniFi UI)."
  type = map(object({
    mac        = string
    fixed_ip   = string
    network_id = optional(string)
    note       = optional(string)
  }))
  default = {}
}

# Adopted from the live controller (import blocks in imports.tf) - the pitower
# cluster nodes' static IPs, previously set by hand per the old "set a UniFi
# reservation" notes in ansible/README.md and ansible/inventory/hosts.yaml.
locals {
  known_reservations = {
    worker-01 = { mac = "1c:83:41:40:88:41", fixed_ip = "10.20.10.1", network_id = unifi_network.servers.id }
    worker-02 = { mac = "1c:83:41:40:66:25", fixed_ip = "10.20.10.2", network_id = unifi_network.servers.id }
    worker-03 = { mac = "1c:83:41:40:65:13", fixed_ip = "10.20.10.3", network_id = unifi_network.servers.id }
    worker-04 = { mac = "10:02:b5:86:00:fb", fixed_ip = "10.20.10.4", network_id = unifi_network.servers.id }
    worker-05 = { mac = "28:d2:44:6d:64:bf", fixed_ip = "10.20.10.5", network_id = unifi_network.servers.id }
    worker-06 = { mac = "50:7b:9d:31:ae:cd", fixed_ip = "10.20.10.6", network_id = unifi_network.servers.id }
    worker-07 = { mac = "bc:24:11:e8:10:19", fixed_ip = "10.20.10.7", network_id = unifi_network.servers.id }
    worker-08 = { mac = "dc:a6:32:4f:95:ca", fixed_ip = "10.20.10.8", network_id = unifi_network.servers.id }
    worker-09 = { mac = "dc:a6:32:4f:ee:e2", fixed_ip = "10.20.10.9", network_id = unifi_network.servers.id }
    worker-10 = { mac = "dc:a6:32:46:b2:ba", fixed_ip = "10.20.10.10", network_id = unifi_network.servers.id }
    data      = { mac = "00:11:32:0c:91:0c", fixed_ip = "10.20.10.100", network_id = unifi_network.servers.id }

    # Proxmox hosts live in 10.20.1.0/24, kept apart from the Kubernetes nodes
    # in 10.20.10.0/24. A PVE cluster's corosync address cannot change after
    # `pvecm create`, so these are pinned before clustering. Everything reaches
    # proxmox-01 by name.
    proxmox-01 = { mac = "f8:bc:12:1d:46:30", fixed_ip = "10.20.1.1", network_id = unifi_network.servers.id, note = "Dell R630, vmbr0 on nic1.20" }
    # ai-01's bare-metal NIC, now the Proxmox host that runs ai-01 as a VM. The
    # ai-01 reservation returns keyed on that VM's MAC once it exists.
    proxmox-02 = { mac = "b0:82:e2:a2:df:33", fixed_ip = "10.20.1.2", network_id = unifi_network.servers.id, note = "ASUS ProArt B850 + RTX 3090 Ti, vmbr0 on nic0.20" }

    # Pinned at its existing dynamic address: nut-exporter and the blackbox
    # probes use the IP, not the name. Also the corosync QDevice for the PVE cluster.
    nut = { mac = "b8:27:eb:52:78:a3", fixed_ip = "10.20.85.197", network_id = unifi_network.servers.id, note = "NUT server + PVE QDevice" }

    # HAOS Pi 4. Pinned on the iot VLAN because two things resolve it by name:
    # the Envoy Gateway Backend behind ha.wibrow.dev
    # (kubernetes/apps/pitower/home-automation/home-assistant/service.yaml) and
    # the button-plus MQTT broker URL (iot/button-plus/office-device-config.json), which
    # hardcodes this exact address. DHCP comes from the tagged vlan101 link, so
    # the MAC is end0's - a VLAN sub-interface inherits its parent's.
    homeassistant = { mac = "dc:a6:32:4f:ee:a9", fixed_ip = "10.101.13.61", network_id = unifi_network.iot.id, note = "HAOS Pi 4 + PoE HAT, tagged VLAN 101 on end0" }
  }
}

# Same controller record (same MAC), so rename in place. Removing ai-01 and
# adding a new key would destroy+create, and skip_forget_on_destroy leaves the
# old record holding its fixed IP (api.err.DuplicateFixedIP).
moved {
  from = unifi_user.reservation["ai-01"]
  to   = unifi_user.reservation["proxmox-02"]
}

resource "unifi_user" "reservation" {
  for_each = merge(local.known_reservations, var.reservations)

  name       = each.key
  mac        = each.value.mac
  fixed_ip   = each.value.fixed_ip
  network_id = try(each.value.network_id, null)
  note       = try(each.value.note, null)

  # Reservations target existing DHCP clients (the device already connected
  # once and got a dynamic lease) - take over management rather than error.
  allow_existing = true

  # Keep the client's history/name in the controller if the reservation is
  # ever removed from Terraform, instead of the controller forgetting it.
  skip_forget_on_destroy = true
}
