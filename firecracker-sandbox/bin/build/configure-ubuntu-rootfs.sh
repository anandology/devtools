#!/bin/bash
# Configure an Ubuntu rootfs image for Firecracker VMs
#
# This script customizes a base Ubuntu rootfs with:
#   - Static network configuration (systemd-networkd)
#   - Hostname
#   - User account with SSH key
#   - fstab for Firecracker drives
#
# This script is intended to be run from within a chroot environment.

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

usage() {
    cat << 'EOF'
Usage: ./configure-ubuntu-rootfs.sh [options]

Configure an Ubuntu rootfs for Firecracker VMs.
This script must be run from within a chroot environment.

Options:
  --hostname NAME       Set hostname (default: ubuntu-vm)
  --ip ADDRESS          Set static IP address (required)
  --gateway ADDRESS     Set gateway IP (default: 172.16.0.1)
  --dns SERVERS         Set DNS servers (default: 8.8.8.8,8.8.4.4)
  --user NAME           Create user account with sudo access (default: ubuntu)
  --ssh-key PATH        Path to SSH public key file (must be accessible from chroot)
  --root-password PASS  Set root password (default: root)
  -h, --help            Show this help message

Examples:
  # Basic configuration with static IP
  ./configure-ubuntu-rootfs.sh --ip 172.16.0.2

  # Full configuration with user and SSH key
  ./configure-ubuntu-rootfs.sh \
    --hostname myvm \
    --ip 172.16.0.2 \
    --user anand \
    --ssh-key /tmp/id_ed25519.pub
EOF
    exit 0
}

# Defaults
HOSTNAME="ubuntu-vm"
GUEST_IP=""
GATEWAY_IP="172.16.0.1"
DNS_SERVERS="8.8.8.8,8.8.4.4"
USERNAME="ubuntu"
SSH_KEY_PATH=""
ROOT_PASSWORD="root"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --ip)
            GUEST_IP="$2"
            shift 2
            ;;
        --gateway)
            GATEWAY_IP="$2"
            shift 2
            ;;
        --dns)
            DNS_SERVERS="$2"
            shift 2
            ;;
        --user)
            USERNAME="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --root-password)
            ROOT_PASSWORD="$2"
            shift 2
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            error "Unexpected argument: $1"
            ;;
    esac
done

# Validate arguments
if [[ -z "$GUEST_IP" ]]; then
    error "--ip is required"
fi

if [[ -n "$SSH_KEY_PATH" ]] && [[ ! -f "$SSH_KEY_PATH" ]]; then
    error "SSH key file not found: $SSH_KEY_PATH"
fi

info "Configuring Ubuntu rootfs"
info "  Hostname: $HOSTNAME"
info "  IP: $GUEST_IP/24"
info "  Gateway: $GATEWAY_IP"
info "  User: $USERNAME"

# Configure hostname
info "Setting hostname..."
setup_hostname "$HOSTNAME"
setup_etc_hosts "$HOSTNAME"

# Configure networking with systemd-networkd
info "Configuring network..."
setup_networking "$GUEST_IP/24" "$GATEWAY_IP" "$DNS_SERVERS"

# Configure fstab
info "Configuring fstab..."
setup_fstab / /home
mkdir -p /home

# Set root password
info "Setting root password..."
set_password root "$ROOT_PASSWORD"

# Configure SSH for root
info "Configuring SSH..."
setup_sshd yes yes yes

# Create user account
info "Creating user account '$USERNAME'..."
# Home will be on separate volume
useradd --no-create-home --home-dir "/home/$USERNAME" -s /bin/bash -G sudo "$USERNAME" 2>/dev/null || true

# Allow sudo without password
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$USERNAME"
chmod 0440 /etc/sudoers.d/"$USERNAME"

# Set up SSH key for user if provided
if [[ -n "$SSH_KEY_PATH" ]]; then
    setup_ssh_keys "$USERNAME" "$SSH_KEY_PATH"
    info "  Added SSH key for $USERNAME"
fi

info ""
info "========================================="
info "  Configuration complete"
info "========================================="
info "Hostname: $HOSTNAME"
info "Network: $GUEST_IP/24 (gateway $GATEWAY_IP)"
info "User: $USERNAME (sudo enabled)"
info "Root password: $ROOT_PASSWORD"
info ""
