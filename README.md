# LAP-Cluster – OpenShift & Talos Homelab on KVM

This repository provisions an OpenShift or Talos Linux cluster in a homelab environment:

- **Terraform** creates VMs on a KVM host (libvirt) and manages Talos ISOs dynamically.
- **Sushy-Tools** provides a Redfish API to dynamically retrieve VM information (BMC emulation).
- **Ansible** orchestrates the entire deployment, including UniFi networking and cluster bootstrapping.
- **UniFi Integration** creates DNS records and Client entries (Fixed IP/VLAN Override) on your Dream Machine.

## Features

- **Multi-Cloud-Native**: Supports both **OpenShift** (Agent-Based Installer) and **Talos Linux**.
- **Single Entry Point**: Infrastructure and cluster deployment are orchestrated through a single `ansible-navigator` command.
- **Single Source of Truth**: All variables (IPs, MACs, Cluster settings) are defined centrally in `inventory/group_vars/all.yml`.
- **IPv4/IPv6 Dual-Stack**: Full support for IPv4 and IPv6 ULA across all components.
- **UniFi Integration**: Automatically creates static client mappings and idempotent DNS records.
- **Redfish BMC Emulation**: Uses `sushy-tools` for Virtual Media boot, treating VMs like bare-metal servers.

## Quick Start

1. **Prepare Environment**
   - Install `ansible-navigator` and a container engine.
   - Ensure `sushy-tools` is running on your host.

2. **Adjust Variables & Credentials**
   ```bash
   cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
   # Edit variables (cluster_type, IPs, MACs, Pull Secret, UniFi settings)
   ```

3. **Deploy Cluster**
   ```bash
   export $(cat .env | xargs) && ansible-navigator run playbooks/site.yml
   ```

4. **Cleanup Everything**
   ```bash
   export $(cat .env | xargs) && ansible-navigator run playbooks/destroy.yml
   ```

## Workflow

1. **Phase 0: Infrastructure (Terraform)**
   - Provisions libvirt networks, storage, and VMs.
   - **Talos**: Automatically fetches the correct ISO via Talos Image Factory and mounts it.
2. **Phase 0.4: UniFi Client Provisioning**
   - Registers MACs in UniFi with Fixed IPs and VLAN Overrides.
3. **Phase 0.5: DNS Provisioning**
   - Creates A/AAAA records for nodes and API/Ingress VIPs.
4. **Phase 1-4: Cluster Specific Deployment**
   - **OpenShift**: Downloads installer, builds Agent ISO, boots nodes, and waits for install.
   - **Talos**: Generates secrets, boots nodes (using the Terraform-managed ISO), and bootstraps the cluster.
5. **Phase 5: Day-2 Configuration**
   - Post-install tweaks and health checks.

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