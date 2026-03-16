# Gemini CLI Project Context: LAP-Cluster (OpenShift on KVM)

This file provides system-level context, architectural guidelines, and technical constraints for AI agents operating within this repository.

## 1. Project Overview & Architecture
This project automates the deployment of an OpenShift 4.x cluster in a homelab environment using a combination of Terraform and Ansible.

**Core Components:**
*   **Infrastructure Provider:** KVM/libvirt managed via Terraform (`dmacvicar/libvirt`).
*   **BMC Emulator:** `sushy-tools` is used to provide a Redfish API for libvirt VMs, allowing the OpenShift Agent-Based Installer to perform Bare Metal (Virtual Media) PXE-like booting.
*   **Networking:** UniFi Dream Machine (UDM). The cluster utilizes VLAN 13.
*   **Orchestration:** Ansible, executed exclusively via `ansible-navigator` utilizing an Execution Environment (EE).

## 2. Tech Stack & Key Conventions
*   **Terraform (>= 1.5):** Strict adherence to the `dmacvicar/libvirt` provider v0.9.x schema (requires nested blocks like `ips`, `domain`, `devices.disks.source.volume`, `os.boot_devices`).
*   **Ansible (>= 2.15):** 
    *   Always use Fully Qualified Collection Names (FQCN), e.g., `ansible.builtin.file`, `ubiquiti.unifi_api.network`.
    *   Do not use the deprecated `community.general.yaml` callback. Use `ansible.builtin.default` with `result_format = yaml`.
*   **State Management:** `inventory/group_vars/all.yml` is the **single source of truth**. Terraform variables (`terraform.tfvars.json`) are dynamically generated from this file during Phase 0.

## 3. Critical Network Constraints (Dual-Stack)
*   The cluster operates in a **Dual-Stack (IPv4 / IPv6)** mode.
*   All Terraform network definitions, OpenShift installer configurations (`install-config.yaml`, `agent-config.yaml`), and DNS records must handle both IPv4 and IPv6 ULA (e.g., `fd60::/64`) addresses.

## 4. UniFi API Quirks & Workarounds (CRITICAL)
Interacting with the UniFi Dream Machine requires a split approach due to bugs in the official Ansible collection and the unavailability of certain features in the v1 API.

*   **Rule 1: Official v1 Endpoints:** For endpoints like `/v1/sites`, `/v1/sites/{site_id}/networks`, and `/v1/sites/{site_id}/dns/policies`, **always** use the official `ubiquiti.unifi_api.network` module.
*   **Rule 2: Legacy Proxy Endpoints:** To manage Client static IPs and VLAN Overrides, the official v1 API is insufficient. You **must** use raw HTTP requests via `ansible.builtin.uri` targeting the legacy endpoints (`/proxy/network/api/s/...`).
*   **Rule 3: Authentication:** When using `ansible.builtin.uri` against the UniFi proxy, always provide the token in the headers as both `X-API-Key` and `Authorization: Bearer` to ensure successful authentication.

## 5. Workflows
*   **Execution:** All playbooks must be executed via `ansible-navigator` to ensure the correct Execution Environment is used (which mounts libvirt sockets and SSH keys).
    *   *Example:* `export $(cat .env | xargs) && ansible-navigator run playbooks/site.yml`
*   **Testing/Idempotency:** All Ansible roles (especially DNS and Client provisioning) must be strictly idempotent. Always check for the existence of a resource (via `GET`) before attempting to create or update it (`POST`/`PUT`).

## 6. Directory Structure Rules
*   `terraform/`: Contains all HCL code. No hardcoded variables; everything must accept inputs from the generated `terraform.tfvars.json`.
*   `playbooks/`: Sequentially numbered phases (e.g., `00-infrastructure.yml`, `00.4-unifi-clients.yml`, `00.5-dns.yml`).
*   `inventory/dynamic_inventory.py`: Must maintain the fallback logic to parse `group_vars/all.yml` if the Terraform state or Redfish API is unreachable during the initial run.
