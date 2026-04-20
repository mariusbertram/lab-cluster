# -----------------------------------------------------------------------------
# VM Module – creates a single KVM VM for OpenShift
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

resource "libvirt_volume" "os_disk" {
  name     = "${var.vm_name}-os.qcow2"
  pool     = var.pool_name
  capacity = var.disk_size * 1024 * 1024 * 1024 # GiB → Bytes

  target = {
    format = {
      type = "raw"
    }
  }
}

resource "libvirt_domain" "vm" {
  name        = var.vm_name
  vcpu        = var.vcpu
  memory      = var.memory
  memory_unit = "MiB"
  type        = "kvm"

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
    
    loader          = "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd"
    loader_readonly = "yes"
    loader_type     = "pflash"
    nv_ram = {
      # Use the "clean" VARS template to start in UEFI Setup Mode
      template = "/usr/share/edk2/ovmf/OVMF_VARS.fd"
      nv_ram   = "/var/lib/libvirt/qemu/nvram/uefi-${var.vm_name}.fd"
    }
  }

  features = {
    acpi = true
    # SMM is required for Secure Boot
    smm  = {
      state = "on"
    }
  }

  devices = {
    disks = [
      {
        # OS DISK - ALWAYS FIRST
        source = {
          volume = {
            pool   = var.pool_name
            volume = libvirt_volume.os_disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        boot_order = "1"
      }
    ]

    interfaces = [
      {
        source = { network = {
          network = var.network_name
          }
        }
        mac = {
        address = var.mac_address }
        model = {
          type = "virtio"
        }
        boot_order = "2"
      }
    ]

    graphics = [
      { spice = {
        auto_port = true
        image = {
          compression = "off"
        }
      } }
    ]

    consoles = [
      {
        type        = "pty"
        target_port = "0"
        target_type = "serial"
      }
    ]
  }

  # VM stays off until Ansible boots it via Redfish/Sushy
  running = var.start_vm

  lifecycle {
    ignore_changes = [running]
  }
}
