# LAP-Cluster – OpenShift Homelab on KVM

This repository provisions an OpenShift cluster in a homelab environment:

- **Terraform** creates VMs on a KVM host (libvirt)
- **Sushy-Tools** provides a Redfish API to dynamically retrieve VM information (BMC emulation)
- **Ansible** deploys OpenShift via the **Agent-Based Installer** and configures the cluster (Day-2)

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  KVM Host (libvirt)                                  │
│                                                      │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐        │
│  │master-0│ │master-1│ │master-2│ │worker-0│  ...    │
│  └────────┘ └────────┘ └────────┘ └────────┘        │
│                                                      │
│  Sushy-Tools (Redfish BMC Emulator)  :8000           │
│  Terraform libvirt provider                          │
└──────────────────────────────────────────────────────┘
         │
         │ Ansible (Agent-Based Installer)
         ▼
   OpenShift Cluster
```

## Prerequisites

- KVM host with libvirt, QEMU
- Terraform >= 1.5
- Ansible >= 2.15
- `sushy-tools` installed on the KVM host
- OpenShift pull secret (`pull-secret.json`)
- SSH key pair

## Quick Start

```bash
# 1. Adjust variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp ansible/inventory/group_vars/all.yml.example ansible/inventory/group_vars/all.yml

# 2. Create infrastructure
cd terraform
terraform init
terraform plan
terraform apply

# 3. Deploy OpenShift (inventory is automatically loaded from Terraform)
cd ../ansible
ansible-playbook playbooks/site.yml

# Alternative: Query inventory only from Redfish
INVENTORY_SOURCE=redfish ansible-playbook playbooks/site.yml
```

## Dynamic Inventory

The Ansible inventory is **automatically** populated from one of two sources:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | **Terraform State** | Reads `terraform output -json ansible_inventory` – contains all IPs, MACs, Redfish IDs |
| 2 | **Redfish / Sushy-Tools** | Queries `GET /redfish/v1/Systems`, discovers VMs by name (master-*/worker-*) |

### Configuration via Environment Variables

```bash
# Default: Terraform first, then Redfish as fallback
INVENTORY_SOURCE=auto    # (Default)

# Terraform only
INVENTORY_SOURCE=terraform

# Redfish / Sushy-Tools only
INVENTORY_SOURCE=redfish

# Additional configuration
TERRAFORM_DIR=/path/to/terraform
SUSHY_HOST=192.168.1.100
SUSHY_PORT=8000
KVM_HOST=192.168.1.100
KVM_USER=root
```

### Test the Inventory

```bash
# Display full inventory
./ansible/inventory/dynamic_inventory.py --list | jq .

# Query a single host
./ansible/inventory/dynamic_inventory.py --host master-0 | jq .

# Ansible inventory graph
cd ansible && ansible-inventory --graph
```

## Directory Structure

```
.
├── terraform/                  # VM provisioning on KVM
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf              # incl. ansible_inventory output
│   ├── versions.tf
│   ├── modules/
│   │   └── vm/                 # Reusable VM module
│   └── terraform.tfvars.example
│
├── ansible/                    # OpenShift deployment & configuration
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── dynamic_inventory.py  # Dynamic: Terraform → Redfish fallback
│   │   └── group_vars/
│   │       └── all.yml.example
│   ├── playbooks/
│   │   ├── site.yml
│   │   ├── 01-prepare-installer.yml
│   │   ├── 02-generate-agent-iso.yml
│   │   ├── 03-boot-nodes.yml
│   │   ├── 04-wait-for-install.yml
│   │   └── 05-day2-config.yml
│   ├── roles/
│   │   ├── ocp_installer/
│   │   ├── redfish_boot/
│   │   └── day2_config/
│   └── templates/
│       ├── install-config.yaml.j2
│       └── agent-config.yaml.j2
│
├── scripts/                    # Helper scripts
│   ├── setup-sushy-tools.sh
│   └── destroy-cluster.sh
│
└── docs/                       # Documentation
    └── architecture.md
```
