#!/bin/bash
# Build a standard Ubuntu rootfs for Firecracker VMs
#
# This creates a vanilla Ubuntu rootfs with systemd and openssh-server.
# No custom configuration is applied - use configure-ubuntu-rootfs.sh for that.

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
Usage: sudo ./build-ubuntu-rootfs.sh <version> <output_path>

Build a standard Ubuntu rootfs ext4 image for Firecracker VMs.

This creates a vanilla Ubuntu image with:
  - systemd init system
  - openssh-server
  - sudo
  - Default root password: root

No custom networking, users, or SSH keys are configured.
Use configure-ubuntu-rootfs.sh to customize the image.

Arguments:
  version       Ubuntu version: 20.04, 22.04, or 24.04
  output_path   Path to output ext4 image file

Environment variables:
  IMAGE_SIZE_MB     Size of the ext4 image in MB (default: 2048)

Examples:
  sudo ./build-ubuntu-rootfs.sh 24.04 /tmp/ubuntu-24.04.ext4
  sudo IMAGE_SIZE_MB=4096 ./build-ubuntu-rootfs.sh 22.04 ./rootfs.ext4
EOF
    exit 0
}

# Handle --help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
fi

# Check required arguments
if [[ $# -lt 2 ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}" >&2
    echo "" >&2
    echo "Usage: sudo ./build-ubuntu-rootfs.sh <version> <output_path>" >&2
    echo "Run with --help for more information." >&2
    exit 1
fi

# Configuration
UBUNTU_VERSION="$1"
OUTPUT_PATH="$2"
IMAGE_SIZE_MB="${IMAGE_SIZE_MB:-2048}"

# Map version to codename
case "$UBUNTU_VERSION" in
    24.04) UBUNTU_CODENAME="noble" ;;
    22.04) UBUNTU_CODENAME="jammy" ;;
    20.04) UBUNTU_CODENAME="focal" ;;
    *) error "Unsupported Ubuntu version: $UBUNTU_VERSION. Supported: 20.04, 22.04, 24.04" ;;
esac

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo"
fi

# Check for required tools
for cmd in mkfs.ext4 mount umount chroot; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is not installed. Install with: sudo apt install e2fsprogs util-linux"
    fi
done

# Check for debootstrap or Docker
check_docker() {
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

check_debootstrap_support() {
    local codename="$1"
    if [[ -f "/usr/share/debootstrap/scripts/$codename" ]] || \
       [[ -L "/usr/share/debootstrap/scripts/$codename" ]]; then
        return 0
    fi
    return 1
}

HAS_DEBOOTSTRAP=false
HAS_DOCKER=false

if command -v debootstrap &> /dev/null; then
    HAS_DEBOOTSTRAP=true
fi

if check_docker; then
    HAS_DOCKER=true
fi

if [[ "$HAS_DEBOOTSTRAP" == false ]] && [[ "$HAS_DOCKER" == false ]]; then
    error "Either debootstrap or Docker is required.\n  Install: sudo apt install debootstrap\n  Or install Docker"
fi

info "Building Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME) rootfs..."
info "  Output: $OUTPUT_PATH"
info "  Size: ${IMAGE_SIZE_MB}MB"

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
mkdir -p "$OUTPUT_DIR"

# Create temporary directory for rootfs
ROOTFS_TEMP=$(mktemp -d)
trap "rm -rf $ROOTFS_TEMP" EXIT

# Run debootstrap
run_debootstrap_host() {
    info "Running debootstrap (host)..."
    debootstrap --include=systemd,openssh-server,linux-image-virtual,init,sudo \
        "$UBUNTU_CODENAME" "$ROOTFS_TEMP" http://archive.ubuntu.com/ubuntu/
}

run_debootstrap_docker() {
    info "Running debootstrap via Docker..."
    docker run --rm --privileged \
        -v "$ROOTFS_TEMP:/target" \
        "ubuntu:$UBUNTU_VERSION" \
        bash -c "apt-get update -qq && \
                 apt-get install -y -qq debootstrap && \
                 debootstrap --include=systemd,openssh-server,linux-image-virtual,init,sudo \
                     $UBUNTU_CODENAME /target http://archive.ubuntu.com/ubuntu/"
}

if [[ "$HAS_DEBOOTSTRAP" == true ]] && check_debootstrap_support "$UBUNTU_CODENAME"; then
    run_debootstrap_host
elif [[ "$HAS_DOCKER" == true ]]; then
    run_debootstrap_docker
else
    error "Host debootstrap doesn't support $UBUNTU_CODENAME and Docker is not available"
fi

# Minimal configuration - just enough to boot
info "Applying minimal configuration..."

# Set default root password
chroot "$ROOTFS_TEMP" bash -c "echo 'root:root' | chpasswd"

# Enable SSH service (but don't configure it)
chroot "$ROOTFS_TEMP" systemctl enable ssh

# Create ext4 filesystem image
info "Creating ext4 image (${IMAGE_SIZE_MB}MB)..."
dd if=/dev/zero of="$OUTPUT_PATH" bs=1M count=$IMAGE_SIZE_MB status=progress
mkfs.ext4 -F "$OUTPUT_PATH"

# Mount and copy files
MOUNT_POINT=$(mktemp -d)
trap "umount $MOUNT_POINT 2>/dev/null || true; rm -rf $MOUNT_POINT $ROOTFS_TEMP" EXIT

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
info "  Ubuntu rootfs built successfully"
info "========================================="
info "Output: $OUTPUT_PATH"
info "Size: $ACTUAL_SIZE"
info "Ubuntu: $UBUNTU_VERSION ($UBUNTU_CODENAME)"
info "Root password: root"
info ""
info "Next step: configure the image with"
info "  sudo ./configure-ubuntu-rootfs.sh $OUTPUT_PATH --ip 172.16.0.2 ..."
info ""
