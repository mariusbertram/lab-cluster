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

variable "network_id" {
  description = "ID of the libvirt network"
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

variable "boot_iso_path" {
  description = "Path to the boot ISO (Agent-Based Installer)"
  type        = string
  default     = ""
}

variable "start_vm" {
  description = "Whether to start the VM immediately (false = Sushy boot via Ansible)"
  type        = bool
  default     = false
}
