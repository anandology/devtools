#!/bin/bash
set -e

# Global system setup for Firecracker VM framework
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

# Check prerequisites
info "Checking prerequisites..."

# Check KVM support
if [[ ! -e /dev/kvm ]]; then
    error "/dev/kvm not found. KVM support is required."
fi

if [[ ! -r /dev/kvm ]] || [[ ! -w /dev/kvm ]]; then
    warn "User $SUDO_USER doesn't have access to /dev/kvm"
    info "Adding user to kvm group..."
    usermod -aG kvm "$SUDO_USER"
    warn "Please log out and back in for group changes to take effect"
fi

# Check for required tools
for cmd in ip iptables systemctl curl; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is not installed. Please install it first."
    fi
done

# Download Firecracker binary if not present
FIRECRACKER_BIN="$BIN_DIR/firecracker"
if [[ ! -x "$FIRECRACKER_BIN" ]]; then
    info "Downloading Firecracker $FIRECRACKER_VERSION..."
    FIRECRACKER_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-x86_64.tgz"
    
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    curl -L "$FIRECRACKER_URL" -o firecracker.tgz
    tar -xzf firecracker.tgz
    
    # Move binary to bin directory
    mv "release-${FIRECRACKER_VERSION}-x86_64/firecracker-${FIRECRACKER_VERSION}-x86_64" "$FIRECRACKER_BIN"
    chmod +x "$FIRECRACKER_BIN"
    chown "$SUDO_USER:$SUDO_USER" "$FIRECRACKER_BIN"
    
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    
    info "✓ Firecracker binary installed to $FIRECRACKER_BIN"
else
    info "✓ Firecracker binary already present"
fi

# Create systemd service for bridge management
info "Creating systemd service for bridge management..."

# Make helper scripts executable
chmod +x "$BIN_DIR/bridge-up.sh" "$BIN_DIR/bridge-down.sh"

SERVICE_FILE="/etc/systemd/system/firecracker-bridge.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Firecracker Bridge Network
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN_DIR/bridge-up.sh
ExecStop=$BIN_DIR/bridge-down.sh

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable firecracker-bridge.service

# Use restart to ensure service uses new configuration (in case it was already running)
systemctl restart firecracker-bridge.service

info "✓ Bridge service created and started"

# Create state directory and symlink
mkdir -p "$STATE_DIR"
chown "$SUDO_USER:$SUDO_USER" "$STATE_DIR"

# Wait for bridge to be created (with retry)
BRIDGE_LINK="$STATE_DIR/bridge"
MAX_RETRIES=10
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if [[ -e "/sys/class/net/$BRIDGE_NAME" ]]; then
        ln -sf "/sys/class/net/$BRIDGE_NAME" "$BRIDGE_LINK"
        info "✓ Bridge $BRIDGE_NAME is active"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
        sleep 0.5
    else
        error "Bridge $BRIDGE_NAME was not created successfully after ${MAX_RETRIES} retries"
    fi
done

# Create other required directories
mkdir -p "$KERNELS_DIR" "$VMS_DIR"
chown -R "$SUDO_USER:$SUDO_USER" "$VMS_ROOT"

info ""
info "========================================="
info "  Firecracker Setup Complete!"
info "========================================="
info "Bridge: $BRIDGE_NAME at $BRIDGE_IP"
info "State: $STATE_DIR"
info ""
info "Next steps:"
info "  1. Initialize a VM: ~/vms/vm.sh init <name>"
info "  2. Edit configuration: ~/vms/vms/<name>/config.sh"
info "  3. Build VM: sudo ~/vms/vm.sh build <name>"
info "  4. Start VM: ~/vms/vm.sh up <name>"
info ""
