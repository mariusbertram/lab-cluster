# -----------------------------------------------------------------------------
# LAP-Cluster – Terraform Main
# Creates VMs on KVM/libvirt for the OpenShift cluster
# -----------------------------------------------------------------------------

# ---------- Network ----------

resource "libvirt_network" "ocp_network" {
  name      = var.network_name
  mode      = "nat"
  domain    = var.cluster_domain
  autostart = true

  addresses = [var.network_cidr]

  dns {
    enabled    = true
    local_only = true

    dynamic "hosts" {
      for_each = merge(
        { for m in var.masters : m.name => m.ip },
        { for w in var.workers : w.name => w.ip },
        { "api.${var.cluster_name}.${var.cluster_domain}" = var.api_vip },
        { "*.apps.${var.cluster_name}.${var.cluster_domain}" = var.ingress_vip }
      )
      content {
        hostname = hosts.key
        ip       = hosts.value
      }
    }
  }

  dhcp { enabled = false }
}

# ---------- Storage Pool ----------

resource "libvirt_pool" "ocp_pool" {
  name = "${var.cluster_name}-pool"
  type = "dir"
  path = var.storage_pool_path
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
  boot_iso_path = var.agent_iso_path
}
