output "ip_address" {
  value = var.ip_address
}

output "ipv6_address" {
  value = var.ipv6_address
}

output "mac_address" {
  value = var.mac_address
}

output "domain_name" {
  description = "Libvirt Domain-Name (für Sushy-Tools Redfish UUID Lookup)"
  value       = libvirt_domain.vm.name
}

output "domain_id" {
  description = "UUID of the VM"
  value       = libvirt_domain.vm.uuid
}
