# -----------------------------------------------------------------------------
# Outputs – consumed by Ansible
# -----------------------------------------------------------------------------

output "master_ips" {
  description = "IP addresses of the master nodes"
  value       = { for k, m in module.masters : k => m.ip_address }
}

output "worker_ips" {
  description = "IP addresses of the worker nodes"
  value       = { for k, w in module.workers : k => w.ip_address }
}

output "master_macs" {
  description = "MAC addresses of the master nodes"
  value       = { for k, m in module.masters : k => m.mac_address }
}

output "worker_macs" {
  description = "MAC addresses of the worker nodes"
  value       = { for k, w in module.workers : k => w.mac_address }
}

output "master_domain_names" {
  description = "Libvirt domain names of the master VMs (for Sushy-Tools/Redfish)"
  value       = { for k, m in module.masters : k => m.domain_name }
}

output "worker_domain_names" {
  description = "Libvirt domain names of the worker VMs (for Sushy-Tools/Redfish)"
  value       = { for k, w in module.workers : k => w.domain_name }
}

output "network_id" {
  description = "ID of the created libvirt network"
  value       = libvirt_network.ocp_network.id
}

output "api_vip" {
  value = var.api_vip
}

output "ingress_vip" {
  value = var.ingress_vip
}

# -----------------------------------------------------------------------------
# Combined output for the dynamic Ansible inventory
# Written as JSON and consumed by the inventory script
# -----------------------------------------------------------------------------
output "ansible_inventory" {
  description = "Complete node information for the dynamic Ansible inventory"
  value = {
    cluster_name   = var.cluster_name
    cluster_domain = var.cluster_domain
    api_vip        = var.api_vip
    ingress_vip    = var.ingress_vip
    network_cidr   = var.network_cidr
    kvm_host       = var.libvirt_uri

    masters = { for k, m in module.masters : k => {
      ansible_host      = m.ip_address
      mac               = m.mac_address
      redfish_system_id = m.domain_name
      role              = "master"
    } }

    workers = { for k, w in module.workers : k => {
      ansible_host      = w.ip_address
      mac               = w.mac_address
      redfish_system_id = w.domain_name
      role              = "worker"
    } }
  }
}
