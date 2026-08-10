# Adoption of the pre-existing controller config. Without these, an apply from
# empty state tries to CREATE all of it: the run that proved it (actions run
# 31355740386) was rejected by the controller with api.err.VlanUsed /
# api.err.PdRequiresAssignedDhcpv6Wan, so nothing was duplicated, but the
# failure mode is a live-network one and not worth re-testing.
#
# Kept in place after the adopting apply rather than deleted: they are no-ops
# once the resources are in state, and if the state object is ever lost they
# make the rebuild re-adopt what exists instead of re-attempting creates.
#
# IDs are the controller's Mongo ObjectIDs, read from
# /proxy/network/api/s/default/rest/{networkconf,user}.

import {
  to = unifi_network.default
  id = "681e6bf6489d244451d7238d"
}

import {
  to = unifi_network.home
  id = "694f7cea703254181bf71fb8"
}

import {
  to = unifi_network.iot
  id = "694f7c61703254181bf71f50"
}

import {
  to = unifi_network.servers
  id = "694f7d66703254181bf72059"
}

import {
  to = unifi_network.management
  id = "6999629e81307c26099e8998"
}

# Only the codified local.known_reservations have controller IDs to adopt;
# anything added later via var.reservations is a genuine create.
locals {
  known_reservation_ids = {
    worker-01 = "683739bd03aa633e72626434"
    worker-02 = "6836a01e03aa633e7261c77d"
    worker-03 = "68373a0503aa633e726264de"
    worker-04 = "681e4d99abce0339a34baaf1"
    worker-05 = "69fecc0d146696433afbf075"
    worker-06 = "69cfabae5d503efaee0107ba"
    worker-07 = "6a5e87ffba125aaa3cc1b84f"
    worker-08 = "681e4d99abce0339a34baaf3"
    worker-09 = "69c8cd0b5d503efaeee8241b"
    worker-10 = "681e4d99abce0339a34baaf2"
    data      = "681e4d52abce0339a34baaef"
  }
}

import {
  for_each = local.known_reservation_ids

  to = unifi_user.reservation[each.key]
  id = each.value
}
