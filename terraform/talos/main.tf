# -----------------------------------------------------------------------------
# Talos Cluster Configuration & Bootstrapping
# -----------------------------------------------------------------------------

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Generate client configuration from secrets
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.controlplane_nodes[0]]
  nodes                = var.controlplane_nodes
}

# Generate machine configurations for controlplane and worker
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = "1.32.1"
  talos_version      = var.talos_version
  config_patches = compact([
    # Installation Disk Configuration
    yamlencode({
      machine = {
        install = {
          diskSelector = {
            size = "> 50GB"
          }
          wipe = true
        }
      }
    }),
    # API VIP Configuration
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "Layer2VIPConfig"
      link       = var.talos_vip_interface
      name       = var.api_vip
    }),
    # CNI Configuration
    var.talos_cni != "flannel" ? yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
      }
    }) : null,
    # Cilium specific
    var.talos_cni == "cilium" ? yamlencode({
      cluster = {
        proxy = {
          disabled = true
        }
      }
    }) : null
  ])
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = "1.32.1"
  talos_version      = var.talos_version
  config_patches = compact([
    # Installation Disk Configuration
    yamlencode({
      machine = {
        install = {
          diskSelector = {
            size = "> 50GB"
          }
          wipe = true
        }
      }
    }),
    # CNI Configuration
    var.talos_cni != "flannel" ? yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
      }
    }) : null,
    # Cilium specific
    var.talos_cni == "cilium" ? yamlencode({
      cluster = {
        proxy = {
          disabled = true
        }
      }
    }) : null
  ])
}

# Apply configuration to controlplane nodes
resource "talos_machine_configuration_apply" "controlplane" {
  for_each                    = toset(var.controlplane_nodes)
  node                        = each.key
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
}

# Apply configuration to worker nodes
resource "talos_machine_configuration_apply" "worker" {
  for_each                    = toset(var.worker_nodes)
  node                        = each.key
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
}

# Bootstrap the cluster on the first controlplane node
resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  node                 = var.controlplane_nodes[0]
  client_configuration = talos_machine_secrets.this.client_configuration
}

# Retrieve kubeconfig
resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  node                 = var.controlplane_nodes[0]
  client_configuration = talos_machine_secrets.this.client_configuration
}
