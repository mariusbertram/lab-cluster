#!/usr/bin/env python3
"""
Dynamic Ansible inventory for LAP-Cluster.
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
import yaml

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ALL_YML = os.path.join(SCRIPT_DIR, "group_vars", "all.yml")

GLOBAL_VARS = {}
if os.path.exists(ALL_YML):
    with open(ALL_YML, 'r') as f:
        try:
            GLOBAL_VARS = yaml.safe_load(f) or {}
        except yaml.YAMLError:
            pass

TERRAFORM_DIR = os.environ.get("TERRAFORM_DIR", os.path.join(SCRIPT_DIR, "..", "terraform"))
SUSHY_HOST = os.environ.get("SUSHY_HOST", GLOBAL_VARS.get("sushy_host", "192.168.1.100"))
SUSHY_PORT = os.environ.get("SUSHY_PORT", GLOBAL_VARS.get("sushy_port", "8000"))
SUSHY_PROTOCOL = os.environ.get("SUSHY_PROTOCOL", GLOBAL_VARS.get("sushy_protocol", "http"))
SUSHY_USERNAME = os.environ.get("SUSHY_USERNAME", GLOBAL_VARS.get("redfish_username", "admin"))
SUSHY_PASSWORD = os.environ.get("SUSHY_PASSWORD", GLOBAL_VARS.get("redfish_password", "password"))

KVM_HOST = os.environ.get("KVM_HOST", GLOBAL_VARS.get("kvm_host", "localhost"))
KVM_USER = os.environ.get("KVM_USER", GLOBAL_VARS.get("kvm_user", "root"))
INVENTORY_SOURCE = os.environ.get("INVENTORY_SOURCE", "auto")


def empty_inventory():
    return {"_meta": {"hostvars": {}}}


def build_inventory_from_terraform(tf_data):
    hostvars = {}
    master_hosts = []
    worker_hosts = []

    all_vars = GLOBAL_VARS.copy()
    all_vars.update({
        "cluster_name": tf_data.get("cluster_name", all_vars.get("cluster_name", "")),
        "base_domain": tf_data.get("cluster_domain", all_vars.get("base_domain", "")),
        "api_vip": tf_data.get("api_vip", all_vars.get("api_vip", "")),
        "ingress_vip": tf_data.get("ingress_vip", all_vars.get("ingress_vip", "")),
        "network_cidr": tf_data.get("network_cidr", all_vars.get("cluster_network_cidr", "")),
    })

    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {
            "children": ["kvm_host", "bastion", "masters", "workers", "cluster"],
            "vars": all_vars,
        },
        "kvm_host": {"hosts": ["hypervisor"]},
        "bastion": {"hosts": ["hypervisor"]},
        "masters": {"hosts": master_hosts},
        "workers": {"hosts": worker_hosts},
        "cluster": {"children": ["masters", "workers"]},
    }

    hostvars["localhost"] = {"ansible_connection": "local"}
    hostvars["hypervisor"] = {
        "ansible_host": KVM_HOST,
        "ansible_user": KVM_USER,
        "ansible_connection": "local" if KVM_HOST in ("localhost", "127.0.0.1", "::1") else "ssh",
    }

    bmc_address = f"{SUSHY_HOST}:{SUSHY_PORT}"
    master_nodes = []
    for name, info in tf_data.get("masters", {}).items():
        master_hosts.append(name)
        hostvars[name] = {
            "ansible_host": info["ansible_host"],
            "mac": info["mac"],
            "ipv6": info.get("ipv6", ""),
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"],
            "node_role": "master",
        }
        master_nodes.append({
            "name": name,
            "hostname": name,
            "role": "master",
            "ip": info["ansible_host"],
            "ipv6": info.get("ipv6", ""),
            "mac": info["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"]
        })

    worker_nodes = []
    for name, info in tf_data.get("workers", {}).items():
        worker_hosts.append(name)
        hostvars[name] = {
            "ansible_host": info["ansible_host"],
            "mac": info["mac"],
            "ipv6": info.get("ipv6", ""),
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"],
            "node_role": "worker",
        }
        worker_nodes.append({
            "name": name,
            "hostname": name,
            "role": "worker",
            "ip": info["ansible_host"],
            "ipv6": info.get("ipv6", ""),
            "mac": info["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": info["redfish_system_id"]
        })

    inventory["all"]["vars"]["master_nodes"] = master_nodes
    inventory["all"]["vars"]["worker_nodes"] = worker_nodes
    return inventory


def build_inventory_from_vars(vars_data):
    hostvars = {}
    master_hosts = []
    worker_hosts = []
    
    cluster_flavor = vars_data.get("cluster_flavor", "standard")
    
    inventory = {
        "_meta": {"hostvars": hostvars},
        "all": {
            "children": ["kvm_host", "bastion", "masters", "workers", "cluster"],
            "vars": vars_data,
        },
        "kvm_host": {"hosts": ["hypervisor"]},
        "bastion": {"hosts": ["hypervisor"]},
        "masters": {"hosts": master_hosts},
        "workers": {"hosts": worker_hosts},
        "cluster": {"children": ["masters", "workers"]},
    }
    hostvars["localhost"] = {"ansible_connection": "local"}
    hostvars["hypervisor"] = {
        "ansible_host": KVM_HOST,
        "ansible_user": KVM_USER,
        "ansible_connection": "local" if KVM_HOST in ("localhost", "127.0.0.1", "::1") else "ssh",
    }
    bmc_address = f"{SUSHY_HOST}:{SUSHY_PORT}"
    
    master_nodes_list = []
    raw_masters = vars_data.get("nodes", {}).get("masters", [])
    if cluster_flavor == "sno" and raw_masters:
        raw_masters = [raw_masters[0]]
        
    for node in raw_masters:
        name = node["name"]; master_hosts.append(name)
        hostvars[name] = {
            "ansible_host": node["ip"],
            "mac": node["mac"],
            "ipv6": node.get("ipv6", ""),
            "bmc_address": bmc_address,
            "redfish_system_id": name,
            "node_role": "master"
        }
        master_nodes_list.append({
            "name": name,
            "hostname": name,
            "role": "master",
            "ip": node["ip"],
            "ipv6": node.get("ipv6", ""),
            "mac": node["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": name
        })

    worker_nodes_list = []
    raw_workers = vars_data.get("nodes", {}).get("workers", [])
    if cluster_flavor in ("sno", "compact"):
        raw_workers = []
        
    for node in raw_workers:
        name = node["name"]; worker_hosts.append(name)
        hostvars[name] = {
            "ansible_host": node["ip"],
            "mac": node["mac"],
            "ipv6": node.get("ipv6", ""),
            "bmc_address": bmc_address,
            "redfish_system_id": name,
            "node_role": "worker"
        }
        worker_nodes_list.append({
            "name": name,
            "hostname": name,
            "role": "worker",
            "ip": node["ip"],
            "ipv6": node.get("ipv6", ""),
            "mac": node["mac"],
            "bmc_address": bmc_address,
            "redfish_system_id": name
        })

    inventory["all"]["vars"]["master_nodes"] = master_nodes_list
    inventory["all"]["vars"]["worker_nodes"] = worker_nodes_list
    return inventory


def load_from_terraform():
    tf_dir = os.path.realpath(TERRAFORM_DIR)
    if not os.path.isdir(tf_dir): return None
    state_file = os.path.join(tf_dir, "terraform.tfstate")
    if not os.path.isfile(state_file): return None
    try:
        result = subprocess.run(["terraform", "output", "-json", "ansible_inventory"], cwd=tf_dir, capture_output=True, text=True, timeout=30)
        if result.returncode != 0: return None
        return build_inventory_from_terraform(json.loads(result.stdout))
    except: return None


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", action="store_true")
    group.add_argument("--host", help="Host variables")
    args = parser.parse_args()

    inventory = None
    if INVENTORY_SOURCE in ("terraform", "auto"):
        inventory = load_from_terraform()

    if inventory is None and GLOBAL_VARS:
        inventory = build_inventory_from_vars(GLOBAL_VARS)

    if inventory is None: inventory = empty_inventory()
    if args.list: print(json.dumps(inventory, indent=2))
    elif args.host: print(json.dumps(inventory["_meta"]["hostvars"].get(args.host, {}), indent=2))

if __name__ == "__main__":
    main()
