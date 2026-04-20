# -----------------------------------------------------------------------------
# Outputs – consumed by Ansible
# -----------------------------------------------------------------------------

output "controlplane_ips" {
  description = "IP addresses of the controlplane nodes"
  value       = { for k, m in module.controlplanes : k => m.ip_address }
}

output "worker_ips" {
  description = "IP addresses of the worker nodes"
  value       = { for k, w in module.workers : k => w.ip_address }
}

output "controlplane_macs" {
  description = "MAC addresses of the controlplane nodes"
  value       = { for k, m in module.controlplanes : k => m.mac_address }
}

output "worker_macs" {
  description = "MAC addresses of the worker nodes"
  value       = { for k, w in module.workers : k => w.mac_address }
}

output "controlplane_domain_names" {
  description = "Libvirt domain names of the controlplane VMs (for Sushy-Tools/Redfish)"
  value       = { for k, m in module.controlplanes : k => m.domain_name }
}

output "worker_domain_names" {
  description = "Libvirt domain names of the worker VMs (for Sushy-Tools/Redfish)"
  value       = { for k, w in module.workers : k => w.domain_name }
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
    cluster_name      = var.cluster_name
    cluster_domain    = var.cluster_domain
    api_vip           = var.api_vip
    api_vip_ipv6      = var.api_vip_ipv6
    ingress_vip       = var.ingress_vip
    ingress_vip_ipv6  = var.ingress_vip_ipv6
    network_cidr      = "${var.network_address}/${var.network_prefix}"
    network_ipv6_cidr = "${var.network_ipv6_address}/${var.network_ipv6_prefix}"
    kvm_host          = var.libvirt_uri
    talos_iso_url     = var.cluster_type == "talos" ? data.talos_image_factory_urls.this[0].urls.iso : ""

    controlplanes = { for k, v in module.controlplanes : k => {
      ansible_host      = v.ip_address
      mac               = v.mac_address
      ipv6              = v.ipv6_address
      redfish_system_id = v.domain_id
      role              = "controlplane"
    } }

    workers = { for k, v in module.workers : k => {
      ansible_host      = v.ip_address
      mac               = v.mac_address
      ipv6              = v.ipv6_address
      redfish_system_id = v.domain_id
      role              = "worker"
    } }
  }
}
