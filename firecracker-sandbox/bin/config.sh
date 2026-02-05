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
# Using the latest 6.x kernel available for Firecracker v1.7
KERNEL_VERSION="6.1.77"
KERNEL_URL="https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.7/x86_64/vmlinux-${KERNEL_VERSION}"

# Framework paths - determine ROOT based on script location
# Scripts are in $ROOT/bin/, so ROOT is parent of bin directory
# Use BASH_SOURCE to get config.sh location (works when sourced)
CONFIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMS_ROOT="${VMS_ROOT:-$(dirname "$CONFIG_SCRIPT_DIR")}"
KERNELS_DIR="$VMS_ROOT/kernels"
STATE_DIR="$VMS_ROOT/state"
VMS_DIR="$VMS_ROOT/vms"
BIN_DIR="$VMS_ROOT/bin"
