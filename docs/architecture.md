# Architecture

## Overview

```
                    ┌─────────────────────────┐
                    │     Workstation         │
                    │  (Terraform + Ansible)  │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │      KVM Host           │
                    │                         │
                    │  ┌──────────────────┐   │
                    │  │  Sushy-Tools     │   │
                    │  │  (Redfish API)   │   │
                    │  │  :8000           │   │
                    │  └────────┬─────────┘   │
                    │           │ libvirt     │
                    │  ┌────────▼─────────┐   │
                    │  │    VMs (KVM)     │   │
                    │  │                  │   │
                    │  │ master-0  (.20)  │   │
                    │  │ master-1  (.21)  │   │
                    │  │ master-2  (.22)  │   │
                    │  │ worker-0  (.30)  │   │
                    │  └──────────────────┘   │
                    └─────────────────────────┘
```

## Workflow

### Phase 1: Infrastructure (Terraform)
1. Create libvirt network with DNS
2. Create storage pool
3. Create VMs with OS disks (but do **not** start them)
4. VMs have the agent ISO mounted as CD-ROM

### Phase 2: OpenShift Deployment (Ansible)
1. **Prepare installer**: Download `openshift-install` + `oc` CLI
2. **Generate agent ISO**: Template `install-config.yaml` + `agent-config.yaml` → build ISO
3. **Boot nodes**: Insert virtual media and start VMs via Sushy-Tools Redfish API
4. **Wait for installation**: Bootstrap → Install Complete
5. **Day-2 configuration**: Approve CSRs, verify cluster operators

## Sushy-Tools / Redfish

Sushy-Tools emulates a Redfish BMC interface for libvirt VMs:

- **List systems**: `GET /redfish/v1/Systems/`
- **Get VM info**: `GET /redfish/v1/Systems/{vm-name}`
- **Virtual Media**: `POST /redfish/v1/Systems/{vm-name}/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia`
- **Power Control**: `POST /redfish/v1/Systems/{vm-name}/Actions/ComputerSystem.Reset`

This allows Ansible to treat the VMs like real bare-metal servers.
