#!/bin/bash
# Configure an Ubuntu rootfs image for Firecracker VMs
#
# This script customizes a base Ubuntu rootfs with:
#   - Static network configuration (systemd-networkd)
#   - Hostname
#   - User account with SSH key
#   - fstab for Firecracker drives

set -euo pipefail

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
Usage: sudo ./configure-ubuntu-rootfs.sh <image_path> [options]

Configure an Ubuntu rootfs ext4 image for Firecracker VMs.

Arguments:
  image_path    Path to the ext4 rootfs image to configure

Options:
  --hostname NAME       Set hostname (default: ubuntu-vm)
  --ip ADDRESS          Set static IP address (required)
  --gateway ADDRESS     Set gateway IP (default: 172.16.0.1)
  --dns SERVERS         Set DNS servers (default: 8.8.8.8,8.8.4.4)
  --user NAME           Create user account with sudo access
  --ssh-key PATH        Path to SSH public key file
  --root-password PASS  Set root password (default: root)
  --fstab               Configure fstab for /dev/vda (root) and /dev/vdb (home)
  -h, --help            Show this help message

Examples:
  # Basic configuration with static IP
  sudo ./configure-ubuntu-rootfs.sh rootfs.ext4 --ip 172.16.0.2

  # Full configuration with user and SSH key
  sudo ./configure-ubuntu-rootfs.sh rootfs.ext4 \
    --hostname myvm \
    --ip 172.16.0.2 \
    --user anand \
    --ssh-key ~/.ssh/id_ed25519.pub \
    --fstab
EOF
    exit 0
}

# Defaults
HOSTNAME="ubuntu-vm"
GUEST_IP=""
GATEWAY_IP="172.16.0.1"
DNS_SERVERS="8.8.8.8,8.8.4.4"
USERNAME=""
SSH_KEY_PATH=""
ROOT_PASSWORD="root"
CONFIGURE_FSTAB=false

# Parse arguments
if [[ $# -lt 1 ]]; then
    usage
fi

IMAGE_PATH=""

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
        --fstab)
            CONFIGURE_FSTAB=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            if [[ -z "$IMAGE_PATH" ]]; then
                IMAGE_PATH="$1"
            else
                error "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$IMAGE_PATH" ]]; then
    error "Image path is required"
fi

if [[ ! -f "$IMAGE_PATH" ]]; then
    error "Image not found: $IMAGE_PATH"
fi

if [[ -z "$GUEST_IP" ]]; then
    error "--ip is required"
fi

if [[ -n "$SSH_KEY_PATH" ]] && [[ ! -f "$SSH_KEY_PATH" ]]; then
    error "SSH key file not found: $SSH_KEY_PATH"
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo"
fi

info "Configuring Ubuntu rootfs: $IMAGE_PATH"
info "  Hostname: $HOSTNAME"
info "  IP: $GUEST_IP/24"
info "  Gateway: $GATEWAY_IP"
if [[ -n "$USERNAME" ]]; then
    info "  User: $USERNAME"
fi

# Mount the image
MOUNT_POINT=$(mktemp -d)
trap "umount $MOUNT_POINT 2>/dev/null || true; rmdir $MOUNT_POINT 2>/dev/null || true" EXIT

mount "$IMAGE_PATH" "$MOUNT_POINT"

# Configure hostname
info "Setting hostname..."
echo "$HOSTNAME" > "$MOUNT_POINT/etc/hostname"
cat > "$MOUNT_POINT/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Configure networking with systemd-networkd
info "Configuring network..."
mkdir -p "$MOUNT_POINT/etc/systemd/network"

# Convert comma-separated DNS to separate lines
DNS_CONFIG=""
IFS=',' read -ra DNS_ARRAY <<< "$DNS_SERVERS"
for dns in "${DNS_ARRAY[@]}"; do
    DNS_CONFIG="${DNS_CONFIG}DNS=$dns
"
done

cat > "$MOUNT_POINT/etc/systemd/network/10-eth0.network" << EOF
[Match]
Name=eth0

[Network]
Address=$GUEST_IP/24
Gateway=$GATEWAY_IP
$DNS_CONFIG
EOF

# Enable systemd-networkd
chroot "$MOUNT_POINT" systemctl enable systemd-networkd 2>/dev/null || true

# Configure fstab if requested
if [[ "$CONFIGURE_FSTAB" == true ]]; then
    info "Configuring fstab..."
    cat > "$MOUNT_POINT/etc/fstab" << EOF
# <device>  <mount>  <type>  <options>  <dump>  <pass>
/dev/vda    /        ext4    defaults   0       1
/dev/vdb    /home    ext4    defaults,nofail   0       2
EOF
    mkdir -p "$MOUNT_POINT/home"
fi

# Set root password
info "Setting root password..."
chroot "$MOUNT_POINT" bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Configure SSH for root
info "Configuring SSH..."
cat >> "$MOUNT_POINT/etc/ssh/sshd_config" << 'EOF'

# Custom configuration
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
EOF

# Set up root SSH key if provided and no user specified
if [[ -n "$SSH_KEY_PATH" ]] && [[ -z "$USERNAME" ]]; then
    ROOT_SSH_DIR="$MOUNT_POINT/root/.ssh"
    mkdir -p "$ROOT_SSH_DIR"
    cp "$SSH_KEY_PATH" "$ROOT_SSH_DIR/authorized_keys"
    chmod 700 "$ROOT_SSH_DIR"
    chmod 600 "$ROOT_SSH_DIR/authorized_keys"
    info "  Added SSH key for root"
fi

# Create user account if specified
if [[ -n "$USERNAME" ]]; then
    info "Creating user account '$USERNAME'..."
    
    if [[ "$CONFIGURE_FSTAB" == true ]]; then
        # Home will be on separate volume
        chroot "$MOUNT_POINT" useradd --no-create-home --home-dir "/home/$USERNAME" -s /bin/bash -G sudo "$USERNAME" 2>/dev/null || true
    else
        # Create home on rootfs
        chroot "$MOUNT_POINT" useradd --create-home -s /bin/bash -G sudo "$USERNAME" 2>/dev/null || true
    fi
    
    # Allow sudo without password
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$MOUNT_POINT/etc/sudoers.d/$USERNAME"
    chmod 0440 "$MOUNT_POINT/etc/sudoers.d/$USERNAME"
    
    # Set up SSH key for user if provided
    if [[ -n "$SSH_KEY_PATH" ]]; then
        USER_SSH_DIR="$MOUNT_POINT/home/$USERNAME/.ssh"
        mkdir -p "$USER_SSH_DIR"
        cp "$SSH_KEY_PATH" "$USER_SSH_DIR/authorized_keys"
        
        # Get UID/GID from the image
        USER_UID=$(chroot "$MOUNT_POINT" id -u "$USERNAME")
        USER_GID=$(chroot "$MOUNT_POINT" id -g "$USERNAME")
        
        chown -R "$USER_UID:$USER_GID" "$USER_SSH_DIR"
        chmod 700 "$USER_SSH_DIR"
        chmod 600 "$USER_SSH_DIR/authorized_keys"
        info "  Added SSH key for $USERNAME"
    fi
fi

# Sync and unmount
sync
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"
trap - EXIT

info ""
info "========================================="
info "  Configuration complete"
info "========================================="
info "Image: $IMAGE_PATH"
info "Hostname: $HOSTNAME"
info "Network: $GUEST_IP/24 (gateway $GATEWAY_IP)"
if [[ -n "$USERNAME" ]]; then
    info "User: $USERNAME (sudo enabled)"
fi
info "Root password: $ROOT_PASSWORD"
info ""
