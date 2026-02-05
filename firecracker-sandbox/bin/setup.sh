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

SERVICE_FILE="/etc/systemd/system/firecracker-bridge.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Firecracker Bridge Network
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes

ExecStart=/bin/bash -c '\
    # Create bridge \
    ip link add $BRIDGE_NAME type bridge 2>/dev/null || true; \
    ip addr add $BRIDGE_IP dev $BRIDGE_NAME 2>/dev/null || true; \
    ip link set $BRIDGE_NAME up; \
    \
    # Enable IP forwarding \
    sysctl -w net.ipv4.ip_forward=1 > /dev/null; \
    \
    # Set up NAT rules \
    HOST_IFACE=\$(ip route | grep default | awk "{print \\\$5}" | head -n1); \
    iptables -t nat -C POSTROUTING -o "\$HOST_IFACE" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "\$HOST_IFACE" -j MASQUERADE; \
    iptables -C FORWARD -i $BRIDGE_NAME -o "\$HOST_IFACE" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i $BRIDGE_NAME -o "\$HOST_IFACE" -j ACCEPT; \
    iptables -C FORWARD -i "\$HOST_IFACE" -o $BRIDGE_NAME -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "\$HOST_IFACE" -o $BRIDGE_NAME -m state --state RELATED,ESTABLISHED -j ACCEPT; \
'

ExecStop=/bin/bash -c '\
    # Remove NAT rules \
    HOST_IFACE=\$(ip route | grep default | awk "{print \\\$5}" | head -n1); \
    iptables -t nat -D POSTROUTING -o "\$HOST_IFACE" -j MASQUERADE 2>/dev/null || true; \
    iptables -D FORWARD -i $BRIDGE_NAME -o "\$HOST_IFACE" -j ACCEPT 2>/dev/null || true; \
    iptables -D FORWARD -i "\$HOST_IFACE" -o $BRIDGE_NAME -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true; \
    \
    # Remove bridge \
    ip link set $BRIDGE_NAME down 2>/dev/null || true; \
    ip link delete $BRIDGE_NAME 2>/dev/null || true; \
'

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable firecracker-bridge.service
systemctl start firecracker-bridge.service

info "✓ Bridge service created and started"

# Create state directory and symlink
mkdir -p "$STATE_DIR"
chown "$SUDO_USER:$SUDO_USER" "$STATE_DIR"

# Create symlink to bridge interface
BRIDGE_LINK="$STATE_DIR/bridge"
if [[ -e "/sys/class/net/$BRIDGE_NAME" ]]; then
    ln -sf "/sys/class/net/$BRIDGE_NAME" "$BRIDGE_LINK"
    info "✓ Bridge $BRIDGE_NAME is active"
else
    error "Bridge $BRIDGE_NAME was not created successfully"
fi

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
