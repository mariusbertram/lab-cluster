# Architecture

## Overview

```
                    ┌─────────────────────────┐
                    │     Workstation         │
                    │  (Terraform + Ansible)  │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼─────────────┐
                    │      KVM Host            │
                    │                          │
                    │  ┌──────────────────┐    │
                    │  │  Sushy-Tools     │    │
                    │  │  (Redfish API)   │    │
                    │  │  :8000           │    │
                    │  └────────┬─────────┘    │
                    │           │ libvirt      │
                    │  ┌────────▼──────────┐   │
                    │  │    VMs (KVM)      │   │
                    │  │                   │   │
                    │  │controlplane-0(.20)│   │
                    │  │controlplane-1(.21)│   │
                    │  │controlplane-2(.22)│   │
                    │  │ worker-0  (.30)   │   │
                    │  └───────────────────┘   │
                    └──────────────────────────┘
```

## Workflow

### Phase 1: Infrastructure (Terraform)
1. Create libvirt network with DNS
2. Create storage pool
3. **Talos**: Fetch ISO via Image Factory and create libvirt volume
4. Create VMs with OS disks (but do **not** start them)
5. VMs have the appropriate ISO (central Talos ISO or per-node Agent ISO) mounted as CD-ROM

### Phase 2: Cluster Deployment (Ansible)

#### For OpenShift:
1. **Prepare installer**: Download `openshift-install` + `oc` CLI
2. **Generate agent ISO**: Template `install-config.yaml` + `agent-config.yaml` → build ISO
3. **Boot nodes**: Insert per-node virtual media and start VMs via Sushy-Tools Redfish API
4. **Wait for installation**: Bootstrap → Install Complete

#### For Talos:
1. **Generate Secrets**: Use `talosctl` to create cluster secrets
2. **Boot nodes**: Start VMs via Sushy-Tools Redfish API (central ISO is already mounted by Terraform)
3. **Bootstrap Cluster**: Run Talos bootstrap via the `siderolabs/talos` Terraform provider

## Sushy-Tools / Redfish

Sushy-Tools emulates a Redfish BMC interface for libvirt VMs:

- **List systems**: `GET /redfish/v1/Systems/`
- **Get VM info**: `GET /redfish/v1/Systems/{vm-uuid}`
- **Virtual Media**: `POST /redfish/v1/Systems/{vm-uuid}/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia`
- **Power Control**: `POST /redfish/v1/Systems/{vm-uuid}/Actions/ComputerSystem.Reset`

This allows Ansible to treat the VMs like real bare-metal servers.
