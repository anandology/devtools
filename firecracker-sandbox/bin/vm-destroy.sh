#!/bin/bash
set -e

# VM Destroy Command - Completely remove a VM instance

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo"
fi

# Check arguments
if [[ $# -lt 1 ]]; then
    error "VM name required. Usage: sudo vm.sh destroy <name>"
fi

VM_NAME="$1"
FORCE=false

# Check for --force flag
if [[ $# -gt 1 ]] && [[ "$2" == "--force" ]]; then
    FORCE=true
fi

VM_DIR="$VMS_DIR/$VM_NAME"
STATE_DIR_VM="$VM_DIR/state"

# Validation
if [[ ! -d "$VM_DIR" ]]; then
    error "VM '$VM_NAME' does not exist"
fi

# Confirmation prompt (unless --force)
if [[ "$FORCE" != true ]]; then
    warn "========================================="
    warn "  WARNING: Destructive Operation"
    warn "========================================="
    warn "This will permanently delete:"
    warn "  - VM files (rootfs, home volume)"
    warn "  - All data in the VM"
    warn "  - Configuration files"
    warn "  - TAP device"
    warn ""
    read -p "Destroy VM '$VM_NAME'? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Destroy cancelled"
        exit 0
    fi
fi

# Stop VM if running
if [[ -f "$STATE_DIR_VM/vm.pid" ]]; then
    PID=$(cat "$STATE_DIR_VM/vm.pid")
    if kill -0 "$PID" 2>/dev/null; then
        info "Stopping running VM..."
        
        # Try to use vm-down.sh as the user
        if sudo -u "$SUDO_USER" "$SCRIPT_DIR/vm-down.sh" "$VM_NAME" 2>/dev/null; then
            info "✓ VM stopped gracefully"
        else
            warn "Could not stop gracefully, killing process..."
            kill -KILL "$PID" 2>/dev/null || true
            sleep 1
        fi
    fi
fi

# Remove TAP device and associated FORWARD rules
if [[ -f "$STATE_DIR_VM/tap_name.txt" ]]; then
    TAP_NAME=$(cat "$STATE_DIR_VM/tap_name.txt")
else
    TAP_NAME="tap-$VM_NAME"
fi

# Remove per-TAP FORWARD rule
HOST_IFACE=$(cat "$STATE_DIR_VM/host_iface.txt" 2>/dev/null || detect_host_interface)
if [[ -n "$HOST_IFACE" ]]; then
    iptables -D FORWARD -i "$TAP_NAME" -o "$HOST_IFACE" -j ACCEPT 2>/dev/null || true
fi

# Delete TAP device
if ip link show "$TAP_NAME" &>/dev/null; then
    info "Removing TAP device $TAP_NAME..."
    ip link delete "$TAP_NAME" 2>/dev/null || warn "Could not remove TAP device"
fi

# Delete VM files
info "Removing VM files..."
rm -rf "$VM_DIR"

info ""
info "========================================="
info "  VM '$VM_NAME' destroyed"
info "========================================="
info ""
