#!/bin/bash
set -e

# Global system cleanup for Firecracker VM framework
# This script must be run with sudo

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

warn "========================================="
warn "  Firecracker Cleanup"
warn "========================================="
warn "This will:"
warn "  - Stop all running VMs"
warn "  - Destroy all VM instances"
warn "  - Remove the bridge network"
warn "  - Remove systemd service"
warn ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Cleanup cancelled"
    exit 0
fi

# Stop and destroy all VMs
if [[ -d "$VMS_DIR" ]]; then
    info "Stopping and destroying all VMs..."
    for vm_dir in "$VMS_DIR"/*/ ; do
        if [[ -d "$vm_dir" ]]; then
            vm_name=$(basename "$vm_dir")
            info "Processing VM: $vm_name"
            
            # Stop VM if running (as user)
            if [[ -f "$vm_dir/state/vm.pid" ]]; then
                pid=$(cat "$vm_dir/state/vm.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    info "  Stopping VM..."
                    sudo -u "$SUDO_USER" "$SCRIPT_DIR/../vm.sh" down "$vm_name" 2>/dev/null || true
                fi
            fi
            
            # Destroy VM (requires sudo for TAP removal)
            if [[ -f "$vm_dir/state/tap_name.txt" ]]; then
                tap_name=$(cat "$vm_dir/state/tap_name.txt")
                if ip link show "$tap_name" &>/dev/null; then
                    info "  Removing TAP device $tap_name..."
                    ip link delete "$tap_name" 2>/dev/null || true
                fi
            fi
            
            # Remove VM directory
            info "  Removing VM files..."
            rm -rf "$vm_dir"
        fi
    done
fi

# Stop and disable systemd service
info "Stopping firecracker-bridge service..."
systemctl stop firecracker-bridge.service 2>/dev/null || true
systemctl disable firecracker-bridge.service 2>/dev/null || true

# Remove systemd service file
SERVICE_FILE="/etc/systemd/system/firecracker-bridge.service"
if [[ -f "$SERVICE_FILE" ]]; then
    info "Removing systemd service file..."
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
fi

# Remove state directory
if [[ -d "$STATE_DIR" ]]; then
    info "Removing state directory..."
    rm -rf "$STATE_DIR"
fi

info ""
info "========================================="
info "  Cleanup Complete!"
info "========================================="
info "All Firecracker VM components have been removed."
info ""
