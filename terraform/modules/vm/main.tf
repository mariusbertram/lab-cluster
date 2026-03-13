# -----------------------------------------------------------------------------
# VM Module – creates a single KVM VM for OpenShift
# -----------------------------------------------------------------------------

resource "libvirt_volume" "os_disk" {
  name   = "${var.vm_name}-os.qcow2"
  pool   = var.pool_name
  format = "qcow2"
  size   = var.disk_size * 1024 * 1024 * 1024 # GiB → Bytes
}

resource "libvirt_domain" "vm" {
  name   = var.vm_name
  vcpu   = var.vcpu
  memory = var.memory

  cpu {
    mode = "host-passthrough"
  }

  # Boot order: CD-ROM (ISO) → hard disk
  boot_device {
    dev = ["cdrom", "hd"]
  }

  disk {
    volume_id = libvirt_volume.os_disk.id
  }

  # Mount Agent-Based Installer ISO as CD-ROM
  dynamic "disk" {
    for_each = var.boot_iso_path != "" ? [1] : []
    content {
      file = var.boot_iso_path
    }
  }

  network_interface {
    network_id     = var.network_id
    mac            = var.mac_address
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }

  # VM stays off until Ansible boots it via Redfish/Sushy
  running = var.start_vm

  lifecycle {
    ignore_changes = [running]
  }
}
