#!/bin/bash
# Build Alpine Linux test rootfs for fast integration tests
# Usage: sudo ./build-alpine-rootfs.sh [output_path] [alpine_version]
#
# This creates a lightweight Alpine Linux rootfs (~10MB) that boots in ~500ms
# Network is configured statically: 172.16.0.2/24 with gateway 172.16.0.1

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

# Configuration
ALPINE_VERSION="${2:-3.19}"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
OUTPUT_PATH="${1:-$(dirname "$0")/../../tests/images/alpine-test.ext4}"
IMAGE_SIZE_MB="${IMAGE_SIZE_MB:-50}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"

# Derived values
ALPINE_ARCH="x86_64"
MINIROOTFS_URL="$ALPINE_MIRROR/v${ALPINE_VERSION}/releases/$ALPINE_ARCH/alpine-minirootfs-${ALPINE_VERSION}.0-$ALPINE_ARCH.tar.gz"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo"
fi

# Check for required tools
for cmd in curl tar mkfs.ext4 mount umount chroot; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is not installed. Install with: sudo apt install curl tar e2fsprogs"
    fi
done

info "Building Alpine Linux test rootfs..."
info "  Version: $ALPINE_VERSION"
info "  Output: $OUTPUT_PATH"
info "  Size: ${IMAGE_SIZE_MB}MB"

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
mkdir -p "$OUTPUT_DIR"

# Create temporary directories
ROOTFS_TEMP=$(mktemp -d)
DOWNLOAD_DIR=$(mktemp -d)
trap "umount $ROOTFS_TEMP 2>/dev/null || true; rm -rf $ROOTFS_TEMP $DOWNLOAD_DIR" EXIT

# Download Alpine minirootfs
MINIROOTFS_FILE="$DOWNLOAD_DIR/alpine-minirootfs.tar.gz"
info "Downloading Alpine minirootfs..."
if ! curl -fsSL "$MINIROOTFS_URL" -o "$MINIROOTFS_FILE"; then
    error "Failed to download Alpine minirootfs from $MINIROOTFS_URL"
fi

# Extract rootfs
info "Extracting rootfs..."
tar -xzf "$MINIROOTFS_FILE" -C "$ROOTFS_TEMP"

# Configure hostname
info "Configuring system..."
echo "alpine-test" > "$ROOTFS_TEMP/etc/hostname"

# Configure hosts file
cat > "$ROOTFS_TEMP/etc/hosts" << 'EOF'
127.0.0.1   localhost localhost.localdomain
127.0.1.1   alpine-test
::1         localhost localhost.localdomain
EOF

# Configure networking with static IP
info "Configuring static network (172.16.0.2/24)..."
mkdir -p "$ROOTFS_TEMP/etc/network"
cat > "$ROOTFS_TEMP/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 172.16.0.2
    netmask 255.255.255.0
    gateway 172.16.0.1
    up echo nameserver 8.8.8.8 > /etc/resolv.conf
    up echo nameserver 8.8.4.4 >> /etc/resolv.conf
EOF

# Configure resolv.conf
cat > "$ROOTFS_TEMP/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Configure APK repositories
info "Configuring APK repositories..."
cat > "$ROOTFS_TEMP/etc/apk/repositories" << EOF
$ALPINE_MIRROR/v${ALPINE_VERSION}/main
$ALPINE_MIRROR/v${ALPINE_VERSION}/community
EOF

# Set up DNS for chroot operations
cp /etc/resolv.conf "$ROOTFS_TEMP/etc/resolv.conf"

# Mount essential filesystems for chroot
mount -t proc proc "$ROOTFS_TEMP/proc"
mount -t sysfs sys "$ROOTFS_TEMP/sys"
mount -o bind /dev "$ROOTFS_TEMP/dev"
trap "umount $ROOTFS_TEMP/proc $ROOTFS_TEMP/sys $ROOTFS_TEMP/dev 2>/dev/null || true; rm -rf $ROOTFS_TEMP $DOWNLOAD_DIR" EXIT

# Install essential packages in chroot
info "Installing OpenSSH server and essential packages..."
chroot "$ROOTFS_TEMP" /bin/sh << 'CHROOT_EOF'
set -e

# Update package index
apk update

# Install essential packages
apk add --no-cache \
    openssh \
    openrc \
    util-linux \
    e2fsprogs \
    bash \
    curl \
    iputils \
    iproute2 \
    iptables

# Set up OpenRC (Alpine's init system)
rc-update add devfs boot
rc-update add dmesg boot
rc-update add mdev boot
rc-update add hwclock boot
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add syslog boot

rc-update add mount-ro shutdown
rc-update add killprocs shutdown
rc-update add savecache shutdown

rc-update add networking default
rc-update add sshd default

# Configure SSH
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Generate SSH host keys
ssh-keygen -A

# Enable getty for console access
rc-update add local default

CHROOT_EOF

# Set root password
info "Setting root password..."
chroot "$ROOTFS_TEMP" /bin/sh -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Set up SSH keys
info "Setting up SSH access..."
ROOT_SSH_DIR="$ROOTFS_TEMP/root/.ssh"
mkdir -p "$ROOT_SSH_DIR"
chmod 700 "$ROOT_SSH_DIR"

# If a public key exists, add it
if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
    cp "$HOME/.ssh/id_rsa.pub" "$ROOT_SSH_DIR/authorized_keys"
    chmod 600 "$ROOT_SSH_DIR/authorized_keys"
    info "✓ Added SSH key from $HOME/.ssh/id_rsa.pub"
elif [[ -n "${SUDO_USER:-}" ]] && [[ -f "/home/$SUDO_USER/.ssh/id_rsa.pub" ]]; then
    cp "/home/$SUDO_USER/.ssh/id_rsa.pub" "$ROOT_SSH_DIR/authorized_keys"
    chmod 600 "$ROOT_SSH_DIR/authorized_keys"
    info "✓ Added SSH key from /home/$SUDO_USER/.ssh/id_rsa.pub"
else
    warn "No SSH key found, using password authentication only"
fi

# Create a simple test script in the VM
cat > "$ROOTFS_TEMP/root/test.sh" << 'EOF'
#!/bin/sh
# Simple test script to verify VM is working
echo "Alpine Linux test VM"
echo "IP: $(ip addr show eth0 | grep 'inet ' | awk '{print $2}')"
echo "Gateway: $(ip route | grep default | awk '{print $3}')"
ping -c 1 172.16.0.1 && echo "Can ping gateway" || echo "Cannot ping gateway"
ping -c 1 8.8.8.8 && echo "Can reach internet" || echo "Cannot reach internet"
EOF
chmod +x "$ROOTFS_TEMP/root/test.sh"

# Unmount filesystems before creating image
info "Finalizing rootfs..."
umount "$ROOTFS_TEMP/proc" "$ROOTFS_TEMP/sys" "$ROOTFS_TEMP/dev"
trap "rm -rf $ROOTFS_TEMP $DOWNLOAD_DIR" EXIT

# Create ext4 filesystem image
info "Creating ext4 image (${IMAGE_SIZE_MB}MB)..."
dd if=/dev/zero of="$OUTPUT_PATH" bs=1M count=$IMAGE_SIZE_MB status=none
mkfs.ext4 -F "$OUTPUT_PATH" >/dev/null 2>&1

# Mount and copy files
MOUNT_POINT=$(mktemp -d)
trap "umount $MOUNT_POINT 2>/dev/null || true; rm -rf $MOUNT_POINT $ROOTFS_TEMP $DOWNLOAD_DIR" EXIT

mount "$OUTPUT_PATH" "$MOUNT_POINT"
info "Copying files to image..."
cp -a "$ROOTFS_TEMP/"* "$MOUNT_POINT/"
sync
umount "$MOUNT_POINT"
rm -rf "$MOUNT_POINT"

# Set ownership to calling user
if [[ -n "${SUDO_USER:-}" ]]; then
    chown "$SUDO_USER:$SUDO_USER" "$OUTPUT_PATH"
fi

# Get actual file size
ACTUAL_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)

info ""
info "========================================="
info "  Alpine test rootfs built successfully"
info "========================================="
info "Output: $OUTPUT_PATH"
info "Size: $ACTUAL_SIZE"
info "Network: 172.16.0.2/24 (gateway 172.16.0.1)"
info "Root password: $ROOT_PASSWORD"
info "SSH: Enabled (port 22)"
info ""
info "Test with:"
info "  firecracker --config-file config.json"
info ""
