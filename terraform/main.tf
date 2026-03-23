# -----------------------------------------------------------------------------
# LAP-Cluster – Terraform Main
# Creates VMs on KVM/libvirt for the OpenShift cluster
# -----------------------------------------------------------------------------

# ---------- Network ----------

# ---------- Storage Pool ----------

resource "libvirt_pool" "ocp_pool" {
  name = "${var.cluster_name}-pool"
  type = "dir"
  target = {
    path = var.storage_pool_path
  }
}

# ---------- Controlplane Nodes ----------

module "controlplanes" {
  source   = "./modules/vm"
  for_each = { for m in var.controlplanes : m.name => m }

  vm_name       = each.value.name
  vcpu          = each.value.vcpu
  memory        = each.value.memory
  disk_size     = each.value.disk_size
  network_name  = var.network_name
  pool_name     = libvirt_pool.ocp_pool.name
  mac_address   = each.value.mac
  ip_address    = each.value.ip
  ipv6_address  = each.value.ipv6
  boot_iso_path = "${var.storage_pool_path}/agent-${each.value.name}.iso"
}

# ---------- Worker Nodes ----------

module "workers" {
  source   = "./modules/vm"
  for_each = { for w in var.workers : w.name => w }

  vm_name       = each.value.name
  vcpu          = each.value.vcpu
  memory        = each.value.memory
  disk_size     = each.value.disk_size
  network_name  = var.network_name
  pool_name     = libvirt_pool.ocp_pool.name
  mac_address   = each.value.mac
  ip_address    = each.value.ip
  ipv6_address  = each.value.ipv6
  boot_iso_path = "${var.storage_pool_path}/agent-${each.value.name}.iso"
}
