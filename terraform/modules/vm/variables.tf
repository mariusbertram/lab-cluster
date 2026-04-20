variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "vcpu" {
  description = "Number of vCPUs"
  type        = number
  default     = 4
}

variable "memory" {
  description = "RAM in MiB"
  type        = number
  default     = 16384
}

variable "disk_size" {
  description = "OS disk size in GiB"
  type        = number
  default     = 120
}

variable "pool_name" {
  description = "libvirt storage pool name"
  type        = string
}

variable "network_name" {
  description = "Name of the libvirt network"
  type        = string
}

variable "mac_address" {
  description = "MAC address of the VM"
  type        = string
}

variable "ip_address" {
  description = "Static IP address of the VM"
  type        = string
}

variable "ipv6_address" {
  description = "Static IPv6 address of the VM"
  type        = string
}

variable "boot_iso_path" {
  description = "Path to the boot ISO file on the host"
  type        = string
}

variable "start_vm" {
  description = "Whether to start the VM immediately"
  type        = bool
  default     = false
}
