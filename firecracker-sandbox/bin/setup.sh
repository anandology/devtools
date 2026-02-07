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
for cmd in ip iptables curl; do
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

# Enable IP forwarding (persistent)
info "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
info "✓ IP forwarding enabled"

# Set up global NAT (MASQUERADE on host interface)
info "Setting up NAT rules..."
HOST_IFACE=$(detect_host_interface)

if [[ -z "$HOST_IFACE" ]]; then
    error "Could not detect host network interface"
fi

# Add MASQUERADE rule (check if exists first)
iptables -t nat -C POSTROUTING -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o "$HOST_IFACE" -j MASQUERADE

# Add global conntrack FORWARD rule for return traffic
iptables -C FORWARD -i "$HOST_IFACE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$HOST_IFACE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

info "✓ NAT rules configured on $HOST_IFACE"

# Create required directories
mkdir -p "$STATE_DIR" "$KERNELS_DIR" "$VMS_DIR"
chown -R "$SUDO_USER:$SUDO_USER" "$VMS_ROOT"

info ""
info "========================================="
info "  Firecracker Setup Complete!"
info "========================================="
info "NAT: MASQUERADE on $HOST_IFACE"
info "State: $STATE_DIR"
info ""
info "Next steps:"
info "  1. Initialize a VM: ~/vms/vm.sh init <name>"
info "  2. Edit configuration: ~/vms/vms/<name>/config.sh"
info "  3. Build VM: sudo ~/vms/vm.sh build <name>"
info "  4. Start VM: ~/vms/vm.sh up <name>"
info ""
