#!/bin/bash
set -e

# VM Build Command - Build VM images with debootstrap

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

# Check arguments
if [[ $# -lt 1 ]]; then
    error "VM name required. Usage: sudo vm.sh build <name>"
fi

VM_NAME="$1"
VM_DIR="$VMS_DIR/$VM_NAME"
STATE_DIR_VM="$VM_DIR/state"

# Validation
if [[ ! -d "$VM_DIR" ]]; then
    error "VM '$VM_NAME' does not exist. Run: vm.sh init $VM_NAME"
fi

if [[ ! -f "$VM_DIR/config.sh" ]]; then
    error "Config file not found: $VM_DIR/config.sh"
fi

if [[ -f "$VM_DIR/rootfs.ext4" ]]; then
    error "VM '$VM_NAME' is already built. Destroy it first to rebuild."
fi

# Load configuration
info "Loading configuration..."
source "$VM_DIR/config.sh"

# Validate required configuration
if [[ -z "$USERNAME" ]]; then
    error "USERNAME not set in config.sh"
fi

if [[ -z "$SSH_KEY_PATH" ]] || [[ ! -f "$SSH_KEY_PATH" ]]; then
    error "SSH_KEY_PATH not set or file doesn't exist: $SSH_KEY_PATH"
fi

# Read IP and gateway
if [[ ! -f "$STATE_DIR_VM/ip.txt" ]]; then
    error "IP file not found: $STATE_DIR_VM/ip.txt"
fi
GUEST_IP=$(cat "$STATE_DIR_VM/ip.txt")

if [[ ! -f "$STATE_DIR_VM/gateway.txt" ]]; then
    error "Gateway file not found: $STATE_DIR_VM/gateway.txt"
fi
GATEWAY_IP=$(cat "$STATE_DIR_VM/gateway.txt")

info "Building VM '$VM_NAME' with IP $GUEST_IP..."

# Check for required tools
for cmd in mkfs.ext4 mount umount; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is not installed. Install with: sudo apt install e2fsprogs util-linux"
    fi
done

# Download kernel if not present
KERNEL_PATH="$KERNELS_DIR/vmlinux-${KERNEL_VERSION}"
if [[ ! -f "$KERNEL_PATH" ]]; then
    info "Downloading kernel ${KERNEL_VERSION}..."
    mkdir -p "$KERNELS_DIR"
    curl -L "$KERNEL_URL" -o "$KERNEL_PATH"

    # Verify download (check if it's not an error message)
    if [[ $(stat -c%s "$KERNEL_PATH" 2>/dev/null || stat -f%z "$KERNEL_PATH" 2>/dev/null) -lt 1000000 ]]; then
        error "Kernel download failed. File is too small. Check URL: $KERNEL_URL"
    fi

    chmod +r "$KERNEL_PATH"
    chown "$SUDO_USER:$SUDO_USER" "$KERNEL_PATH"
    info "✓ Kernel downloaded"
else
    info "✓ Kernel already present"
fi

# Use or build cached rootfs for this Ubuntu version
ROOTFS_CACHE="$IMAGES_DIR/ubuntu-${UBUNTU_VERSION}-rootfs.ext4"
BUILD_ROOTFS_SCRIPT="$BIN_DIR/build/build-ubuntu-rootfs.sh"

if [[ -f "$ROOTFS_CACHE" ]]; then
    info "Using cached rootfs: $ROOTFS_CACHE"
    cp "$ROOTFS_CACHE" "$VM_DIR/rootfs.ext4"
    info "✓ Rootfs image copied"
else
    info "Building rootfs (this may take a few minutes)..."
    mkdir -p "$IMAGES_DIR"
    "$BUILD_ROOTFS_SCRIPT" --image-size "$ROOTFS_SIZE" "$UBUNTU_VERSION" "$ROOTFS_CACHE"
    cp "$ROOTFS_CACHE" "$VM_DIR/rootfs.ext4"
    info "✓ Rootfs image created and cached"
fi

# Copy first-boot script to rootfs using chroot-image.sh
info "Copying first-boot script..."
FIRST_BOOT_SCRIPT="$BIN_DIR/first-boot.sh"
CHROOT_SCRIPT="$BIN_DIR/build/chroot-image.sh"

if [[ -f "$FIRST_BOOT_SCRIPT" ]]; then
    "$CHROOT_SCRIPT" --root "$VM_DIR/rootfs.ext4" --verbose \
        --copy "$FIRST_BOOT_SCRIPT:/first-boot.sh" \
        /bin/bash -c "chmod 755 /first-boot.sh"
else
    # Create a stub first-boot script
    STUB_SCRIPT=$(mktemp)
    cat > "$STUB_SCRIPT" << 'EOF'
#!/bin/bash
# Stub first-boot script - will be replaced with actual implementation
echo "First boot setup..."
exit 0
EOF
    chmod 755 "$STUB_SCRIPT"
    "$CHROOT_SCRIPT" --root "$VM_DIR/rootfs.ext4" --verbose \
        --copy "$STUB_SCRIPT:/first-boot.sh" \
        /bin/bash -c "chmod 755 /first-boot.sh"
    rm -f "$STUB_SCRIPT"
fi

# Note: Package files will be copied to home volume later
# since user home is on /dev/vdb, not on rootfs

# Create home volume using make-image.sh
info "Creating home volume..."
MAKE_IMAGE_SCRIPT="$BIN_DIR/build/make-image.sh"
"$MAKE_IMAGE_SCRIPT" --size "$HOME_SIZE" --path "$VM_DIR/home.ext4"

info "✓ Home volume created"

# Configure rootfs using configure-ubuntu-rootfs.sh via chroot-image.sh
# This is done after home volume creation so both volumes can be mounted
info "Configuring rootfs..."
CHROOT_SCRIPT="$BIN_DIR/build/chroot-image.sh"

# Copy SSH key to VM directory and temporary location for chroot
cp "$SSH_KEY_PATH" "$VM_DIR/ssh_key.pub"
TEMP_SSH_KEY="$VM_DIR/tmp_ssh_key.pub"
cp "$SSH_KEY_PATH" "$TEMP_SSH_KEY"

# Copy entire bin directory and SSH key into the image, then run configure script
# Note: configure-ubuntu-rootfs.sh will source utils.sh from its SCRIPT_DIR (/tmp/bin/build)
# Mount both rootfs and home volumes so user home is accessible
# The configure script will create the user and set up SSH keys
"$CHROOT_SCRIPT" --root "$VM_DIR/rootfs.ext4" --home "$VM_DIR/home.ext4" --verbose \
    --copy "$BIN_DIR:/tmp/bin" \
    --copy "$TEMP_SSH_KEY:/tmp/ssh_key.pub" \
    /bin/bash -c "/tmp/bin/build/configure-ubuntu-rootfs.sh \
        --hostname '$VM_NAME' \
        --ip '$GUEST_IP' \
        --gateway '$GATEWAY_IP' \
        --dns '8.8.8.8,8.8.4.4' \
        --user '$USERNAME' \
        --ssh-key /tmp/ssh_key.pub \
        --root-password 'root'"

# Clean up temporary SSH key
rm -f "$TEMP_SSH_KEY"

info "✓ Rootfs configured"

# Set up user home directory and copy package files on home volume
info "Setting up user home directory on home volume..."
HOME_MOUNT=$(mktemp -d)
mount "$VM_DIR/home.ext4" "$HOME_MOUNT"

# Get the actual UID:GID of the user from the configured rootfs
MOUNT_ROOTFS=$(mktemp -d)
mount "$VM_DIR/rootfs.ext4" "$MOUNT_ROOTFS"
USER_UID=$(chroot "$MOUNT_ROOTFS" id -u "$USERNAME" 2>/dev/null || echo "1000")
USER_GID=$(chroot "$MOUNT_ROOTFS" id -g "$USERNAME" 2>/dev/null || echo "1000")
umount "$MOUNT_ROOTFS"
rmdir "$MOUNT_ROOTFS"

# Create user home directory if it doesn't exist (configure script may have created it)
mkdir -p "$HOME_MOUNT/$USERNAME"
chown $USER_UID:$USER_GID "$HOME_MOUNT/$USERNAME"
chmod 755 "$HOME_MOUNT/$USERNAME"

# Copy package files to user home
if [[ -f "$VM_DIR/apt-packages.txt" ]]; then
    cp "$VM_DIR/apt-packages.txt" "$HOME_MOUNT/$USERNAME/apt-packages.txt"
    chown $USER_UID:$USER_GID "$HOME_MOUNT/$USERNAME/apt-packages.txt"
fi
if [[ -f "$VM_DIR/packages.nix" ]]; then
    cp "$VM_DIR/packages.nix" "$HOME_MOUNT/$USERNAME/packages.nix"
    chown $USER_UID:$USER_GID "$HOME_MOUNT/$USERNAME/packages.nix"
fi

# Unmount home volume
sync
umount "$HOME_MOUNT"
rm -rf "$HOME_MOUNT"

info "✓ User home directory configured"

# Create TAP device
TAP_NAME="tap-$VM_NAME"
info "Creating TAP device $TAP_NAME..."

if ip link show "$TAP_NAME" &>/dev/null; then
    warn "TAP device $TAP_NAME already exists, reusing it"
else
    ip tuntap add "$TAP_NAME" mode tap user "$SUDO_USER"
    ip addr add "$GATEWAY_IP/24" dev "$TAP_NAME"
    ip link set "$TAP_NAME" up
fi

# Add per-TAP FORWARD rule for outbound traffic
HOST_IFACE=$(detect_host_interface)
iptables -C FORWARD -i "$TAP_NAME" -o "$HOST_IFACE" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$TAP_NAME" -o "$HOST_IFACE" -j ACCEPT

echo "$TAP_NAME" > "$STATE_DIR_VM/tap_name.txt"
echo "$HOST_IFACE" > "$STATE_DIR_VM/host_iface.txt"
info "✓ TAP device created with IP $GATEWAY_IP/24"

# Mark as built
date -Iseconds > "$STATE_DIR_VM/built"

# Set ownership of all files to calling user
chown -R "$SUDO_USER:$SUDO_USER" "$VM_DIR"

info ""
info "========================================="
info "  VM '$VM_NAME' built successfully"
info "========================================="
info "IP: $GUEST_IP"
info "TAP: $TAP_NAME"
info "Rootfs: $VM_DIR/rootfs.ext4"
info "Home: $VM_DIR/home.ext4"
info ""
info "Next: ~/vms/vm.sh up $VM_NAME"
info ""
