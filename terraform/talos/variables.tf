variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Talos API endpoint (e.g., https://192.168.1.10:6443)"
  type        = string
}

variable "api_vip" {
  description = "Virtual IP for the API (IPv4)"
  type        = string
}

variable "api_vip_ipv6" {
  description = "Virtual IP for the API (IPv6)"
  type        = string
  default     = ""
}

variable "talos_vip_interface" {
  description = "Interface name for the VIP"
  type        = string
  default     = "enp1s0"
}

variable "talos_cni" {
  description = "CNI to use (flannel, calico, cilium)"
  type        = string
  default     = "flannel"
}

variable "talos_version" {
  description = "Talos version to use"
  type        = string
  default     = ""
}

variable "controlplane_nodes" {
  description = "List of controlplane node IPs"
  type        = list(string)
}

variable "worker_nodes" {
  description = "List of worker node IPs"
  type        = list(string)
}

variable "kubeconfig_path" {
  description = "Local path to save the kubeconfig"
  type        = string
}
