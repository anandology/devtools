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

# Check if bridge is set up
BRIDGE_LINK="$STATE_DIR/bridge"
if [[ ! -L "$BRIDGE_LINK" ]] || [[ ! -e "$BRIDGE_LINK" ]]; then
    error "Bridge not set up. Run: sudo $BIN_DIR/setup.sh"
fi

info "Initializing VM '$VM_NAME'..."

# Create VM directory structure
mkdir -p "$STATE_DIR_VM"

# Auto-assign IP address
info "Assigning IP address..."
NEXT_IP=""
for i in {2..254}; do
    candidate_ip="172.16.0.$i"
    in_use=false
    
    # Check if IP is already assigned to any VM
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
        NEXT_IP="$candidate_ip"
        break
    fi
done

if [[ -z "$NEXT_IP" ]]; then
    error "No available IP addresses in range 172.16.0.2-254"
fi

echo "$NEXT_IP" > "$STATE_DIR_VM/ip.txt"
info "✓ Assigned IP: $NEXT_IP"

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

# Generate packages.nix
cat > "$VM_DIR/packages.nix" << 'EOF'
# Nix packages to install (space-separated)
go_1_24 nodejs
EOF

info "✓ Created packages.nix"

# Print success message
info ""
info "========================================="
info "  VM '$VM_NAME' initialized"
info "========================================="
info "IP: $NEXT_IP"
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
