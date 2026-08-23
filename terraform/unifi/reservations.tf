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
    ai-01     = { mac = "b0:82:e2:a2:df:33", fixed_ip = "10.20.10.11", network_id = unifi_network.servers.id, note = "3090 GPU / LLM node" }
    data      = { mac = "00:11:32:0c:91:0c", fixed_ip = "10.20.10.100", network_id = unifi_network.servers.id }
  }
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
