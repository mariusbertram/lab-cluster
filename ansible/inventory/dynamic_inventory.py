#!/usr/bin/env python3
"""
Dynamic Ansible inventory for LAP-Cluster.

Data sources (in priority order):
  1. Terraform State  – reads `terraform output -json` from the Terraform directory
  2. Redfish/Sushy-Tools – queries the Redfish API to dynamically discover VMs

Configuration via environment variables:
  TERRAFORM_DIR       – Path to the Terraform directory (Default: ../terraform)
  SUSHY_HOST          – Sushy-Tools host (Default: 192.168.1.100)
  SUSHY_PORT          – Sushy-Tools port (Default: 8000)
  SUSHY_PROTOCOL      – http or https (Default: http)
  SUSHY_USERNAME      – Redfish Basic Auth user (Default: admin)
  SUSHY_PASSWORD      – Redfish Basic Auth password (Default: password)
  KVM_HOST            – IP/hostname of the KVM host (Default: 192.168.1.100)
  KVM_USER            – SSH user for the KVM host (Default: root)
  INVENTORY_SOURCE    – "terraform", "redfish" or "auto" (Default: auto)

Usage:
  ansible-playbook -i inventory/dynamic_inventory.py playbooks/site.yml
  ./inventory/dynamic_inventory.py --list
  ./inventory/dynamic_inventory.py --host master-0
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error
import base64
import ssl

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TERRAFORM_DIR = os.environ.get("TERRAFORM_DIR", os.path.join(SCRIPT_DIR, "..", "..", "terraform"))
SUSHY_HOST = os.environ.get("SUSHY_HOST", "192.168.1.100")
SUSHY_PORT = os.environ.get("SUSHY_PORT", "8000")
SUSHY_PROTOCOL = os.environ.get("SUSHY_PROTOCOL", "http")
SUSHY_USERNAME = os.environ.get("SUSHY_USERNAME", "admin")
SUSHY_PASSWORD = os.environ.get("SUSHY_PASSWORD", "password")
KVM_HOST = os.environ.get("KVM_HOST", "192.168.1.100")
KVM_USER = os.environ.get("KVM_USER", "root")
INVENTORY_SOURCE = os.environ.get("INVENTORY_SOURCE", "auto")


def empty_inventory():
    """Empty Ansible inventory."""
    return {"_meta": {"hostvars": {}}}


# ---------------------------------------------------------------------------
# Source 1: Terraform State
# ---------------------------------------------------------------------------
def load_from_terraform():
    """
    Reads the inventory from the Terraform output `ansible_inventory`.
    Returns None if Terraform is not available or no state exists.
    """
    tf_dir = os.path.realpath(TERRAFORM_DIR)

    if not os.path.isdir(tf_dir):
        return None

    # Check if a state file exists
    state_file = os.path.join(tf_dir, "terraform.tfstate")
    if not os.path.isfile(state_file):
        return None

    try:
        result = subprocess.run(
            ["terraform", "output", "-json", "ansible_inventory"],
            cwd=tf_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return None

        tf_data = json.loads(result.stdout)
        return build_inventory_from_terraform(tf_data)

    except (subprocess.TimeoutExpired, FileNotFoundError, json.JSONDecodeError):
        return None


def build_inventory_from_terraform(tf_data):
    """Builds the Ansible inventory dict from Terraform data."""
    hostvars = {}
    master_hosts = []  # type: list[str]
    worker_hosts = []  # type: list[str]

    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {
            "children": ["kvm_host", "bastion", "masters", "workers", "cluster"],
            "vars": {
                "cluster_name": tf_data.get("cluster_name", ""),
                "base_domain": tf_data.get("cluster_domain", ""),
                "api_vip": tf_data.get("api_vip", ""),
                "ingress_vip": tf_data.get("ingress_vip", ""),
                "network_cidr": tf_data.get("network_cidr", ""),
            },
        },
        "kvm_host": {
            "hosts": ["hypervisor"],
        },
        "bastion": {
            "hosts": ["hypervisor"],
        },
        "masters": {
            "hosts": master_hosts,
        },
        "workers": {
            "hosts": worker_hosts,
        },
        "cluster": {
            "children": ["masters", "workers"],
        },
    }

    # KVM-Host / Bastion
    hostvars["hypervisor"] = {
        "ansible_host": KVM_HOST,
        "ansible_user": KVM_USER,
        "ansible_connection": "ssh",
    }

    bmc_address = f"{SUSHY_HOST}:{SUSHY_PORT}"

    # Master nodes
    master_nodes = []
    for name, info in tf_data.get("masters", {}).items():
        master_hosts.append(name)
        hostvars[name] = {
            "ansible_host": info["ansible_host"],
            "mac": info["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"],
            "node_role": "master",
        }
        master_nodes.append({
            "hostname": name,
            "role": "master",
            "ip": info["ansible_host"],
            "mac": info["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"],
        })

    # Worker nodes
    worker_nodes = []
    for name, info in tf_data.get("workers", {}).items():
        worker_hosts.append(name)
        hostvars[name] = {
            "ansible_host": info["ansible_host"],
            "mac": info["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"],
            "node_role": "worker",
        }
        worker_nodes.append({
            "hostname": name,
            "role": "worker",
            "ip": info["ansible_host"],
            "mac": info["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"],
        })

    # Provide node lists as group_vars (for templates)
    inventory["all"]["vars"]["master_nodes"] = master_nodes
    inventory["all"]["vars"]["worker_nodes"] = worker_nodes

    return inventory


# ---------------------------------------------------------------------------
# Source 2: Redfish / Sushy-Tools API
# ---------------------------------------------------------------------------
def redfish_request(path):
    """HTTP GET against the Sushy-Tools Redfish API."""
    url = f"{SUSHY_PROTOCOL}://{SUSHY_HOST}:{SUSHY_PORT}{path}"
    credentials = base64.b64encode(f"{SUSHY_USERNAME}:{SUSHY_PASSWORD}".encode()).decode()

    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Basic {credentials}")
    req.add_header("Accept", "application/json")

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
        return None


def _extract_ethernet_info(system_data):
    """Extracts IP and MAC address from the EthernetInterfaces of a Redfish system."""
    ip_address = None
    mac_address = None

    eth_uri = system_data.get("EthernetInterfaces", {}).get("@odata.id")
    if not eth_uri:
        return ip_address, mac_address

    eth_collection = redfish_request(eth_uri)
    if not eth_collection or "Members" not in eth_collection:
        return ip_address, mac_address

    for eth_member in eth_collection["Members"]:
        eth_data = redfish_request(eth_member["@odata.id"])
        if not eth_data:
            continue

        # MAC address
        if mac_address is None and "MACAddress" in eth_data:
            mac_address = eth_data["MACAddress"]

        # IPv4 address
        if ip_address is None:
            for ipv4 in eth_data.get("IPv4Addresses", []):
                addr = ipv4.get("Address")
                if addr and addr != "0.0.0.0":
                    ip_address = addr
                    break

        # Both found → done
        if ip_address and mac_address:
            break

    return ip_address, mac_address


def load_from_redfish():
    """
    Discovers VMs dynamically via the Sushy-Tools Redfish API.
    Classifies nodes by name (master-* / worker-*).
    """
    systems = redfish_request("/redfish/v1/Systems")
    if not systems or "Members" not in systems:
        return None

    hostvars = {}
    master_hosts = []  # type: list[str]
    worker_hosts = []  # type: list[str]

    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {
            "children": ["kvm_host", "bastion", "masters", "workers", "cluster"],
            "vars": {},
        },
        "kvm_host": {
            "hosts": ["hypervisor"],
        },
        "bastion": {
            "hosts": ["hypervisor"],
        },
        "masters": {
            "hosts": master_hosts,
        },
        "workers": {
            "hosts": worker_hosts,
        },
        "cluster": {
            "children": ["masters", "workers"],
        },
    }

    # KVM-Host
    hostvars["hypervisor"] = {
        "ansible_host": KVM_HOST,
        "ansible_user": KVM_USER,
        "ansible_connection": "ssh",
    }

    bmc_address = f"{SUSHY_HOST}:{SUSHY_PORT}"
    master_nodes = []
    worker_nodes = []

    for member in systems["Members"]:
        system_uri = member["@odata.id"]
        system_data = redfish_request(system_uri)
        if not system_data:
            continue

        name = system_data.get("Name", system_data.get("Id", "unknown"))
        system_id = system_uri.rstrip("/").split("/")[-1]
        power_state = system_data.get("PowerState", "Unknown")

        # Extract IP + MAC in a single pass
        ip_address, mac_address = _extract_ethernet_info(system_data)

        # Determine role based on name
        if "master" in name.lower() or "control" in name.lower():
            role = "master"
        elif "worker" in name.lower() or "compute" in name.lower():
            role = "worker"
        else:
            # Skip unknown VMs
            continue

        hostvars[name] = {
            "ansible_host": ip_address or "unknown",
            "mac": mac_address or "unknown",
            "bmc_address": bmc_address,
            "redfish_system_id": system_id,
            "redfish_system_uri": system_uri,
            "node_role": role,
            "power_state": power_state,
        }

        node_entry = {
            "hostname": name,
            "role": role,
            "ip": ip_address or "unknown",
            "mac": mac_address or "unknown",
            "bmc_address": bmc_address,
            "redfish_system_id": system_id,
        }

        if role == "master":
            master_hosts.append(name)
            master_nodes.append(node_entry)
        else:
            worker_hosts.append(name)
            worker_nodes.append(node_entry)

    # Only return if nodes were actually found
    if not master_hosts and not worker_hosts:
        return None

    inventory["all"]["vars"]["master_nodes"] = master_nodes
    inventory["all"]["vars"]["worker_nodes"] = worker_nodes

    return inventory


# ---------------------------------------------------------------------------
# Host detail (--host)
# ---------------------------------------------------------------------------
def get_host_vars(hostname, inventory):
    """Returns the host variables for a single host."""
    if inventory and "_meta" in inventory:
        return inventory["_meta"]["hostvars"].get(hostname, {})
    return {}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Dynamic Ansible inventory for LAP-Cluster")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", action="store_true", help="Output full inventory")
    group.add_argument("--host", help="Host variables for a single host")
    args = parser.parse_args()

    inventory = None

    if INVENTORY_SOURCE in ("terraform", "auto"):
        inventory = load_from_terraform()
        if inventory:
            sys.stderr.write("[inventory] Source: Terraform State\n")

    if inventory is None and INVENTORY_SOURCE in ("redfish", "auto"):
        inventory = load_from_redfish()
        if inventory:
            sys.stderr.write("[inventory] Source: Redfish/Sushy-Tools API\n")

    if inventory is None:
        sys.stderr.write("[inventory] WARNING: No data source available. Empty inventory.\n")
        inventory = empty_inventory()

    if args.list:
        print(json.dumps(inventory, indent=2))
    elif args.host:
        print(json.dumps(get_host_vars(args.host, inventory), indent=2))


if __name__ == "__main__":
    main()

