# -----------------------------------------------------------------------------
# LAP-Cluster – Terraform Main
# Creates VMs on KVM/libvirt for the OpenShift cluster
# -----------------------------------------------------------------------------

# ---------- Network ----------

resource "libvirt_network" "ocp_network" {
  name      = var.network_name
  autostart = true

  ips = [
    {
      address = var.network_address
      prefix  = var.network_prefix
    },
    {
      address = var.network_ipv6_address
      prefix  = var.network_ipv6_prefix
      family  = "ipv6"
    }
  ]

  domain = {
    name       = var.cluster_domain
    local_only = "yes"
  }

  dns = {
    enable = "yes"
    host = concat(
      [for m in var.masters : { ip = m.ip, hostnames = [{ hostname = m.name }] }],
      [for w in var.workers : { ip = w.ip, hostnames = [{ hostname = w.name }] }],
      [for m in var.masters : { ip = m.ipv6, hostnames = [{ hostname = m.name }] }],
      [for w in var.workers : { ip = w.ipv6, hostnames = [{ hostname = w.name }] }],
      [{ ip = var.api_vip, hostnames = [{ hostname = "api.${var.cluster_name}.${var.cluster_domain}" }] }],
      [{ ip = var.api_vip_ipv6, hostnames = [{ hostname = "api.${var.cluster_name}.${var.cluster_domain}" }] }],
      [{ ip = var.ingress_vip, hostnames = [{ hostname = "*.apps.${var.cluster_name}.${var.cluster_domain}" }] }],
      [{ ip = var.ingress_vip_ipv6, hostnames = [{ hostname = "*.apps.${var.cluster_name}.${var.cluster_domain}" }] }]
    )
  }
}

# ---------- Storage Pool ----------

resource "libvirt_pool" "ocp_pool" {
  name = "${var.cluster_name}-pool"
  type = "dir"
  target = {
    path = var.storage_pool_path
  }
}

# ---------- Master Nodes ----------

module "masters" {
  source   = "./modules/vm"
  for_each = { for m in var.masters : m.name => m }

  vm_name       = each.value.name
  vcpu          = each.value.vcpu
  memory        = each.value.memory
  disk_size     = each.value.disk_size
  network_id    = libvirt_network.ocp_network.id
  pool_name     = libvirt_pool.ocp_pool.name
  mac_address   = each.value.mac
  ip_address    = each.value.ip
  ipv6_address  = each.value.ipv6
  boot_iso_path = var.agent_iso_path
}

# ---------- Worker Nodes ----------

module "workers" {
  source   = "./modules/vm"
  for_each = { for w in var.workers : w.name => w }

  vm_name       = each.value.name
  vcpu          = each.value.vcpu
  memory        = each.value.memory
  disk_size     = each.value.disk_size
  network_id    = libvirt_network.ocp_network.id
  pool_name     = libvirt_pool.ocp_pool.name
  mac_address   = each.value.mac
  ip_address    = each.value.ip
  ipv6_address  = each.value.ipv6
  boot_iso_path = var.agent_iso_path
}
