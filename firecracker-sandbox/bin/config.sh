#!/bin/bash
# Global configuration for Firecracker VM framework

# Network configuration
BRIDGE_NAME="br-firecracker"
BRIDGE_IP="172.16.0.1/24"
BRIDGE_NET="172.16.0.0/24"

# Firecracker version
FIRECRACKER_VERSION="v1.7.0"

# Detect host interface for NAT
detect_host_interface() {
    ip route | grep default | awk '{print $5}' | head -n1
}

HOST_IFACE=$(detect_host_interface)

# Kernel configuration
KERNEL_VERSION="6.1.102"
KERNEL_URL="https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.7/${KERNEL_VERSION}/x86_64/vmlinux-${KERNEL_VERSION}"

# Framework paths (relative to ~/vms/)
VMS_ROOT="${VMS_ROOT:-$HOME/vms}"
KERNELS_DIR="$VMS_ROOT/kernels"
STATE_DIR="$VMS_ROOT/state"
VMS_DIR="$VMS_ROOT/vms"
BIN_DIR="$VMS_ROOT/bin"
