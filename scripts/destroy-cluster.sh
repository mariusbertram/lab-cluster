#!/usr/bin/env bash
# =============================================================================
# Tear down the cluster and clean up all infrastructure
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

echo "⚠️  WARNING: This will destroy the entire cluster and all VMs!"
read -rp "Are you sure? (yes/no): " confirm
if [[ "${confirm}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "=== Destroying Terraform infrastructure ==="
cd "${PROJECT_DIR}/terraform"
if [[ -f "terraform.tfstate" ]]; then
  terraform destroy -auto-approve
else
  echo "No Terraform state found, skipping..."
fi

echo ""
echo "=== Cleaning up installer artifacts ==="
INSTALLER_WORKDIR="${INSTALLER_WORKDIR:-/opt/ocp-installer}"
if [[ -d "${INSTALLER_WORKDIR}/cluster-config" ]]; then
  rm -rf "${INSTALLER_WORKDIR}/cluster-config"
  echo "Cluster config removed."
fi

echo ""
echo "=== Removing agent ISO ==="
ISO_PATH="${AGENT_ISO_PATH:-/var/lib/libvirt/images/agent.x86_64.iso}"
if [[ -f "${ISO_PATH}" ]]; then
  rm -f "${ISO_PATH}"
  echo "ISO removed: ${ISO_PATH}"
fi

echo ""
echo "✅ Cluster fully destroyed."
