# LAP-Cluster – OpenShift Homelab on KVM

This repository provisions an OpenShift cluster in a homelab environment:

- **Terraform** creates VMs on a KVM host (libvirt)
- **Sushy-Tools** provides a Redfish API to dynamically retrieve VM information (BMC emulation)
- **Ansible** deploys OpenShift via the **Agent-Based Installer** and configures the cluster (Day-2)
- **UniFi Integration** creates DNS records and Client entries (Fixed IP/VLAN Override) on your Dream Machine.

## Architecture

```text
┌──────────────────────────────────────────────────────┐
│  KVM Host (libvirt)                                  │
│                                                      │
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────┐         │
│controlplane-0│ │controlplane-1│ │controlplane-2│ │worker-0│  ...    │
└──────────────┘ └──────────────┘ └──────────────┘ └────────┘         │

│                                                      │
│  Sushy-Tools (Redfish BMC Emulator)  :8000           │
│  Terraform libvirt provider                          │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│  UniFi Dream Machine (Network Controller)            │
│  - VLAN 10 (VM Network)                              │
│  - Static IPs & MAC Mapping                          │
│  - DNS A / AAAA Records                              │
└───────────────────────┬──────────────────────────────┘
                        │
         Ansible (Agent-Based Installer)
                        ▼
                  OpenShift Cluster
```

## Features

- **Single Entry Point**: The entire infrastructure (Terraform) and OpenShift deployment (Ansible) are orchestrated through a single `ansible-navigator` command.
- **Single Source of Truth**: All variables (IPs, MACs, Cluster settings) are defined centrally in `inventory/group_vars/all.yml`.
- **Cluster Flavors**: Supports `standard` (3 Masters, 3+ Workers), `compact` (3 Masters, 0 Workers), and `sno` (Single Node OpenShift) via the `cluster_flavor` variable.
- **IPv4/IPv6 Dual-Stack**: Full support for IPv4 and IPv6 ULA (e.g., `fd60::/64`) across the Libvirt network, OpenShift nodes, and DNS records.
- **UniFi Integration**: Automatically creates static client mappings (bypassing the GUI to set Fixed IPs and VLAN Overrides via legacy proxy endpoints) and idempotent DNS records (A and AAAA).
- **Redfish BMC Emulation**: Uses `sushy-tools` to emulate Redfish. VM UUIDs are used as System IDs to ensure reliable identification by the OpenShift Agent-Based Installer.
- **Automated Teardown**: A dedicated `destroy.yml` playbook cleans up the Libvirt VMs, removes the UniFi clients and DNS entries, and deletes local installation artifacts.

## Prerequisites

- KVM host with libvirt, QEMU
- Terraform >= 1.5
- Ansible >= 2.15 (using `ansible-navigator` with Podman/Docker)
- `sushy-tools` installed on the KVM host
- OpenShift pull secret (`pull-secret.json`)
- SSH key pair
- **UniFi Network Application** (Dream Machine Pro/SE/etc.) with an API Token for authentication.

## Quick Start

1. **Prepare Environment**
   - Install `ansible-navigator` and a container engine (Podman/Docker).
   - Ensure `sushy-tools` is running on your host (see `scripts/setup-sushy-tools.sh`).

2. **Adjust Variables & Credentials**
   ```bash
   cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
   # Edit variables (IPs, MACs, Pull Secret path, UniFi settings)
   
   # Provide your UniFi API token via a .env file (recommended)
   echo "UBIQUITI_API_TOKEN=your_secret_token_here" > .env
   ```

3. **Deploy Cluster**
   ```bash
   # Load the environment variables and start the deployment
   export $(cat .env | xargs) && ansible-navigator run playbooks/site.yml
   ```

4. **Cleanup Everything**
   ```bash
   export $(cat .env | xargs) && ansible-navigator run playbooks/destroy.yml
   ```

## Workflow

The entire deployment is orchestrated by Ansible and divided into phases:

1. **Phase 0: Infrastructure (Terraform)**
   - Generates `terraform.tfvars.json` from Ansible variables.
   - Provisions libvirt networks (Dual-Stack), storage, and VMs.
2. **Phase 0.4: UniFi Client Provisioning**
   - Registers MAC addresses in UniFi, assigning Fixed IPs and overriding the Virtual Network (VLAN).
3. **Phase 0.5: DNS Provisioning**
   - Creates idempotent A and AAAA records for all nodes, the API, and the Ingress wildcard on the UniFi controller.
4. **Phase 1: Prepare Installer**
   - Downloads `openshift-install` and `oc` CLI.
5. **Phase 2: Generate Agent ISO**
   - Templates `install-config.yaml` and `agent-config.yaml` (Dual-Stack).
   - Builds the bootable ISO.
6. **Phase 3: Boot Nodes**
   - Uses the Redfish API (Sushy-Tools) to mount the ISO and start the VMs via Virtual Media.
7. **Phase 4: Wait for Installation**
   - Monitors bootstrap and installation progress.
8. **Phase 5: Day-2 Configuration**
   - Post-install tweaks (CSR approval, Operators check, etc.).

## One Place for Variables

All configuration is centralized in `inventory/group_vars/all.yml`. Terraform variables are automatically generated from this file during Phase 0.

## Execution Environment (EE)

The project is pre-configured to run with `ansible-navigator`. The `ansible-navigator.yml` file handles volume mounts for:
- Libvirt socket (`/var/run/libvirt/libvirt-sock`)
- SSH keys (`~/.ssh`)

This allows running both Terraform and Ansible from within the container while interacting with the host's KVM services.

## Dynamic Inventory

The Ansible inventory is **automatically** populated from one of two sources:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | **Terraform State** | Reads `terraform output -json ansible_inventory` |
| 2 | **Redfish / Sushy-Tools** | Queries `GET /redfish/v1/Systems` (discovery fallback) |

### Test the Inventory

```bash
# Display full inventory
ansible-navigator inventory --list -m stdout

# Query a single host
ansible-navigator inventory --host master-0 -m stdout

# Ansible inventory graph
ansible-navigator inventory --graph -m stdout
```

## Directory Structure

```text
.
├── terraform/                  # VM provisioning on KVM
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf              # incl. ansible_inventory output
│   ├── versions.tf
│   └── modules/
│       └── vm/                 # Reusable VM module
│
├── inventory/                  # Dynamic: Terraform → Redfish fallback
│   ├── dynamic_inventory.py
│   └── group_vars/
│       └── all.yml             # Single place for all variables
│
├── playbooks/                  # Full deployment workflow
│   ├── site.yml
│   ├── 00-infrastructure.yml   # Phase 0: Terraform run
│   ├── 00.4-unifi-clients.yml  # Phase 0.4: UniFi Clients
│   ├── 00.5-dns.yml            # Phase 0.5: UniFi DNS
│   ├── 01-prepare-installer.yml
│   ├── 02-generate-agent-iso.yml
│   ├── 03-boot-nodes.yml
│   ├── 04-wait-for-install.yml
│   ├── 05-day2-config.yml
│   └── destroy.yml             # Full Teardown
│
├── roles/                      # Modular logic
│   ├── ocp_installer/
│   ├── redfish_boot/
│   ├── unifi_client_config/
│   ├── unifi_dns/
│   └── day2_config/
│
├── templates/                  # Jinja2 templates for ISO configs
│   ├── install-config.yaml.j2
│   └── agent-config.yaml.j2
│
├── ansible.cfg                 # Global Ansible settings
├── ansible-navigator.yml       # Execution environment config
├── scripts/                    # Helper scripts
└── docs/                       # Documentation
```