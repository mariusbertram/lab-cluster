#!/usr/bin/env bash
# =============================================================================
# Set up Sushy-Tools on the KVM host
# Provides a Redfish BMC emulation for libvirt VMs
# =============================================================================
set -euo pipefail

SUSHY_CONFIG="/etc/sushy/sushy-emulator.conf"
SUSHY_SERVICE="/etc/systemd/system/sushy-emulator.service"

echo "=== Installing Sushy-Tools ==="
pip3 install sushy-tools

echo "=== Creating configuration directory ==="
mkdir -p /etc/sushy

echo "=== Configuring Sushy emulator ==="
cat > "${SUSHY_CONFIG}" <<'EOF'
SUSHY_EMULATOR_LISTEN_IP = '0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_SSL_KEY = None
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu:///system'
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = False
SUSHY_EMULATOR_BOOT_LOADER_MAP = {
    'UEFI': {
        'x86_64': '/usr/share/OVMF/OVMF_CODE.fd'
    }
}
EOF

echo "=== Creating systemd service ==="
cat > "${SUSHY_SERVICE}" <<'EOF'
[Unit]
Description=Sushy Redfish BMC Emulator
After=network.target libvirtd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/sushy-emulator --config /etc/sushy/sushy-emulator.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "=== Enabling and starting service ==="
systemctl daemon-reload
systemctl enable --now sushy-emulator.service

echo "=== Checking status ==="
systemctl status sushy-emulator.service --no-pager

echo ""
echo "=== Sushy-Tools Redfish API available at: ==="
echo "    http://$(hostname -I | awk '{print $1}'):8000/redfish/v1/"
echo ""
echo "=== Test: ==="
echo "    curl http://localhost:8000/redfish/v1/Systems/"
