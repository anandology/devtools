#!/bin/bash
set -e

# VM Init Command - Create VM configuration without building

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

# Check arguments
if [[ $# -lt 1 ]]; then
    error "VM name required. Usage: vm.sh init <name>"
fi

VM_NAME="$1"

# Validate VM name (alphanumeric, hyphens, underscores)
if [[ ! "$VM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid VM name. Use only alphanumeric characters, hyphens, and underscores."
fi

VM_DIR="$VMS_DIR/$VM_NAME"
STATE_DIR_VM="$VM_DIR/state"

# Check if VM already exists
if [[ -d "$VM_DIR" ]]; then
    error "VM '$VM_NAME' already exists at $VM_DIR"
fi

info "Initializing VM '$VM_NAME'..."

# Create VM directory structure
mkdir -p "$STATE_DIR_VM"

# Auto-assign subnet index (each VM gets its own /24 subnet)
info "Assigning subnet..."
SUBNET_INDEX=""
for i in $(seq 0 255); do
    candidate_ip="${SUBNET_PREFIX}.${i}.2"
    in_use=false

    # Check if this subnet is already assigned to any VM
    for vm_dir in "$VMS_DIR"/*/ ; do
        if [[ -d "$vm_dir" ]] && [[ -f "$vm_dir/state/ip.txt" ]]; then
            existing_ip=$(cat "$vm_dir/state/ip.txt")
            if [[ "$existing_ip" == "$candidate_ip" ]]; then
                in_use=true
                break
            fi
        fi
    done

    if [[ "$in_use" == false ]]; then
        SUBNET_INDEX="$i"
        break
    fi
done

if [[ -z "$SUBNET_INDEX" ]]; then
    error "No available subnets in ${SUBNET_PREFIX}.0-255.0/24 range"
fi

GUEST_IP="${SUBNET_PREFIX}.${SUBNET_INDEX}.2"
GATEWAY_IP="${SUBNET_PREFIX}.${SUBNET_INDEX}.1"

echo "$GUEST_IP" > "$STATE_DIR_VM/ip.txt"
echo "$GATEWAY_IP" > "$STATE_DIR_VM/gateway.txt"
info "✓ Assigned subnet: ${SUBNET_PREFIX}.${SUBNET_INDEX}.0/24 (guest=$GUEST_IP, gateway=$GATEWAY_IP)"

# Detect SSH key
info "Detecting SSH key..."
# Get actual user's home directory (not root's when using sudo)
if [[ -n "$SUDO_USER" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

SSH_KEY_PATH=""
for key in "$USER_HOME/.ssh/id_ed25519.pub" "$USER_HOME/.ssh/id_rsa.pub" "$USER_HOME/.ssh/id_ecdsa.pub"; do
    if [[ -f "$key" ]]; then
        SSH_KEY_PATH="$key"
        info "✓ Found SSH key: $SSH_KEY_PATH"
        break
    fi
done

if [[ -z "$SSH_KEY_PATH" ]]; then
    warn "No SSH key found in ~/.ssh/"
    warn "Please set SSH_KEY_PATH in config.sh after initialization"
    SSH_KEY_PATH="# SSH_KEY_PATH=\"~/.ssh/id_ed25519.pub\"  # Update this path"
else
    SSH_KEY_PATH="SSH_KEY_PATH=\"$SSH_KEY_PATH\""
fi

# Detect username (use actual user, not root when using sudo)
USERNAME="${SUDO_USER:-$USER}"

# Generate config.sh
info "Creating configuration file..."
cat > "$VM_DIR/config.sh" << EOF
# VM Configuration for $VM_NAME
# Edit this file, then run: sudo ~/vms/vm.sh build $VM_NAME

# Resources
CPUS=4
MEMORY=8192
ROOTFS_SIZE="8G"
HOME_SIZE="20G"

# User setup
USERNAME="$USERNAME"
$SSH_KEY_PATH

# Ubuntu version
UBUNTU_VERSION="24.04"  # noble
EOF

info "✓ Created config.sh"

# Generate apt-packages.txt
cat > "$VM_DIR/apt-packages.txt" << 'EOF'
# APT packages to install (one per line)
# Lines starting with # are comments

podman
postgresql
tmux
vim
git
curl
htop
ripgrep
EOF

info "✓ Created apt-packages.txt"

# Generate packages.nix (proper Nix expression)
cat > "$VM_DIR/packages.nix" << 'EOF'
# Nix packages to install
# This is a Nix expression that defines a list of packages to install
# Edit this list to add or remove packages
{ pkgs ? import <nixpkgs> {} }:

with pkgs; [
  # Development tools
  go
  nodejs
  python3
  
  # CLI utilities
  tmux
  vim
  git
  curl
  
  # Add your packages here
  # Find packages at: https://search.nixos.org/packages
]
EOF

info "✓ Created packages.nix"

# Print success message
info ""
info "========================================="
info "  VM '$VM_NAME' initialized"
info "========================================="
info "IP: $GUEST_IP (gateway: $GATEWAY_IP)"
info ""
info "Files created:"
info "  Config:   $VM_DIR/config.sh"
info "  Packages: $VM_DIR/apt-packages.txt"
info "  Nix:      $VM_DIR/packages.nix"
info ""
info "Next steps:"
info "  1. Edit configuration files (optional)"
info "  2. Build VM: sudo ~/vms/vm.sh build $VM_NAME"
info ""
