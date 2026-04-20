# -----------------------------------------------------------------------------
# Talos Image Factory – Dynamically fetch ISO URL and create Libvirt volume
# Only active if cluster_type == "talos"
# -----------------------------------------------------------------------------

data "talos_image_factory_extensions_versions" "this" {
  count         = var.cluster_type == "talos" ? 1 : 0
  talos_version = var.talos_version
  filters = {
    names = ["qemu-guest-agent"]
  }
}

resource "talos_image_factory_schematic" "this" {
  count = var.cluster_type == "talos" ? 1 : 0
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this[0].extensions_info.*.name
      }
      secureboot = {}
    }
  })
}

data "talos_image_factory_urls" "this" {
  count         = var.cluster_type == "talos" ? 1 : 0
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this[0].id
  platform      = "metal"
}

output "talos_iso_url" {
  value = var.cluster_type == "talos" ? data.talos_image_factory_urls.this[0].urls.iso : null
}
