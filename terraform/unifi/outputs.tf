output "reservations" {
  description = "Configured DHCP reservations (client name -> fixed IP)"
  value       = { for name, r in unifi_user.reservation : name => r.fixed_ip }
}
