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

# Check if Docker is available
check_docker() {
    if command -v docker &> /dev/null; then
        # Check if Docker daemon is running and accessible
        if docker info &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

# Check if host debootstrap supports target codename
check_debootstrap_support() {
    local codename="$1"
    # Check if script exists in /usr/share/debootstrap/scripts/
    if [[ -f "/usr/share/debootstrap/scripts/$codename" ]] || \
       [[ -L "/usr/share/debootstrap/scripts/$codename" ]]; then
        return 0
    fi
    return 1
}

# Run debootstrap via Docker
run_debootstrap_docker() {
    local codename="$1"
    local target_dir="$2"
    local ubuntu_version="$3"
    
    info "Using Docker to run debootstrap for Ubuntu $ubuntu_version ($codename)..."
    info "This ensures compatibility regardless of host OS version."
    
    # Run debootstrap inside Docker container with target Ubuntu version
    docker run --rm --privileged \
        -v "$target_dir:/target" \
        "ubuntu:$ubuntu_version" \
        bash -c "apt-get update -qq && \
                 apt-get install -y -qq debootstrap && \
                 debootstrap --include=systemd,openssh-server,linux-image-virtual,init,sudo \
                     $codename /target http://archive.ubuntu.com/ubuntu/"
    
    if [[ $? -ne 0 ]]; then
        error "Docker debootstrap failed"
    fi
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

# Check bridge is set up
BRIDGE_LINK="$STATE_DIR/bridge"
if [[ ! -L "$BRIDGE_LINK" ]] || [[ ! -e "$BRIDGE_LINK" ]]; then
    error "Bridge not set up. Run: sudo $BIN_DIR/setup.sh"
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

# Read IP
if [[ ! -f "$STATE_DIR_VM/ip.txt" ]]; then
    error "IP file not found: $STATE_DIR_VM/ip.txt"
fi
GUEST_IP=$(cat "$STATE_DIR_VM/ip.txt")

info "Building VM '$VM_NAME' with IP $GUEST_IP..."

# Check for required tools
for cmd in mkfs.ext4 mount umount chroot; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is not installed. Install with: sudo apt install e2fsprogs util-linux"
    fi
done

# Check for debootstrap or Docker (at least one required)
HAS_DEBOOTSTRAP=false
HAS_DOCKER=false

if command -v debootstrap &> /dev/null; then
    HAS_DEBOOTSTRAP=true
fi

if check_docker; then
    HAS_DOCKER=true
fi

if [[ "$HAS_DEBOOTSTRAP" == false ]] && [[ "$HAS_DOCKER" == false ]]; then
    error "Either debootstrap or Docker is required. Install one of:\n  sudo apt install debootstrap\n  or install Docker"
fi

# Download kernel if not present
KERNEL_PATH="$KERNELS_DIR/${KERNEL_VERSION}"
if [[ ! -f "$KERNEL_PATH" ]]; then
    info "Downloading kernel ${KERNEL_VERSION}..."
    mkdir -p "$KERNELS_DIR"
    curl -L "$KERNEL_URL" -o "$KERNEL_PATH"
    chmod +r "$KERNEL_PATH"
    chown "$SUDO_USER:$SUDO_USER" "$KERNEL_PATH"
    info "✓ Kernel downloaded"
else
    info "✓ Kernel already present"
fi

# Build rootfs with debootstrap
info "Building rootfs with debootstrap (this may take a few minutes)..."

# Map Ubuntu version to codename
case "$UBUNTU_VERSION" in
    24.04) UBUNTU_CODENAME="noble" ;;
    22.04) UBUNTU_CODENAME="jammy" ;;
    20.04) UBUNTU_CODENAME="focal" ;;
    *) error "Unsupported Ubuntu version: $UBUNTU_VERSION" ;;
esac

# Create temporary directory for rootfs
ROOTFS_TEMP=$(mktemp -d)
trap "rm -rf $ROOTFS_TEMP" EXIT

# Decide whether to use host debootstrap or Docker
USE_DOCKER=false

if [[ "$HAS_DEBOOTSTRAP" == true ]] && check_debootstrap_support "$UBUNTU_CODENAME"; then
    # Host debootstrap supports this version
    info "Running debootstrap for Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)..."
    debootstrap --include=systemd,openssh-server,linux-image-virtual,init,sudo \
        "$UBUNTU_CODENAME" "$ROOTFS_TEMP" http://archive.ubuntu.com/ubuntu/
elif [[ "$HAS_DOCKER" == true ]]; then
    # Use Docker for debootstrap
    USE_DOCKER=true
    run_debootstrap_docker "$UBUNTU_CODENAME" "$ROOTFS_TEMP" "$UBUNTU_VERSION"
else
    error "Host debootstrap doesn't support Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME) and Docker is not available.\n  Install Docker or use a supported Ubuntu version (22.04 or 20.04)."
fi

# Configure hostname
info "Configuring hostname..."
echo "$VM_NAME" > "$ROOTFS_TEMP/etc/hostname"
cat > "$ROOTFS_TEMP/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 $VM_NAME

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Configure networking with systemd-networkd
info "Configuring networking..."
mkdir -p "$ROOTFS_TEMP/etc/systemd/network"
cat > "$ROOTFS_TEMP/etc/systemd/network/10-eth0.network" << EOF
[Match]
Name=eth0

[Network]
Address=$GUEST_IP/24
Gateway=172.16.0.1
DNS=8.8.8.8
DNS=8.8.4.4
EOF

# Enable systemd-networkd
chroot "$ROOTFS_TEMP" systemctl enable systemd-networkd

# Configure SSH
info "Configuring SSH..."
mkdir -p "$ROOTFS_TEMP/etc/ssh"
cat >> "$ROOTFS_TEMP/etc/ssh/sshd_config" << 'EOF'

# Custom configuration
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
EOF

# Enable SSH service
chroot "$ROOTFS_TEMP" systemctl enable ssh

# Create user account
info "Creating user account '$USERNAME'..."
chroot "$ROOTFS_TEMP" useradd -m -s /bin/bash -G sudo "$USERNAME"
# Allow sudo without password for convenience
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$ROOTFS_TEMP/etc/sudoers.d/$USERNAME"
chmod 0440 "$ROOTFS_TEMP/etc/sudoers.d/$USERNAME"

# Set up SSH keys
info "Setting up SSH keys..."
USER_SSH_DIR="$ROOTFS_TEMP/home/$USERNAME/.ssh"
ROOT_SSH_DIR="$ROOTFS_TEMP/root/.ssh"
mkdir -p "$USER_SSH_DIR" "$ROOT_SSH_DIR"

# Copy SSH key
cp "$SSH_KEY_PATH" "$VM_DIR/ssh_key.pub"
cat "$SSH_KEY_PATH" > "$USER_SSH_DIR/authorized_keys"
cat "$SSH_KEY_PATH" > "$ROOT_SSH_DIR/authorized_keys"

# Set permissions
chown -R 1000:1000 "$USER_SSH_DIR"  # UID 1000 is typically the first user
chmod 700 "$USER_SSH_DIR"
chmod 600 "$USER_SSH_DIR/authorized_keys"
chmod 700 "$ROOT_SSH_DIR"
chmod 600 "$ROOT_SSH_DIR/authorized_keys"

# Set root password (optional, for console access)
chroot "$ROOTFS_TEMP" bash -c "echo 'root:root' | chpasswd"

# Copy first-boot script to rootfs
info "Copying first-boot script..."
FIRST_BOOT_SCRIPT="$BIN_DIR/first-boot.sh"
if [[ -f "$FIRST_BOOT_SCRIPT" ]]; then
    cp "$FIRST_BOOT_SCRIPT" "$ROOTFS_TEMP/first-boot.sh"
    chmod 755 "$ROOTFS_TEMP/first-boot.sh"
else
    # Create a stub first-boot script
    cat > "$ROOTFS_TEMP/first-boot.sh" << 'EOF'
#!/bin/bash
# Stub first-boot script - will be replaced with actual implementation
echo "First boot setup..."
exit 0
EOF
    chmod 755 "$ROOTFS_TEMP/first-boot.sh"
fi

# Copy package files to VM
info "Copying package configuration files..."
mkdir -p "$ROOTFS_TEMP/home/$USERNAME"
if [[ -f "$VM_DIR/apt-packages.txt" ]]; then
    cp "$VM_DIR/apt-packages.txt" "$ROOTFS_TEMP/home/$USERNAME/apt-packages.txt"
fi
if [[ -f "$VM_DIR/packages.nix" ]]; then
    cp "$VM_DIR/packages.nix" "$ROOTFS_TEMP/home/$USERNAME/packages.nix"
fi
chown -R 1000:1000 "$ROOTFS_TEMP/home/$USERNAME"

# Create ext4 filesystem image
info "Creating rootfs image..."
ROOTFS_SIZE_MB=$(numfmt --from=iec "$ROOTFS_SIZE" | awk '{print int($1/1024/1024)}')
dd if=/dev/zero of="$VM_DIR/rootfs.ext4" bs=1M count=$ROOTFS_SIZE_MB status=progress
mkfs.ext4 -F "$VM_DIR/rootfs.ext4"

# Mount and copy files
MOUNT_POINT=$(mktemp -d)
trap "umount $MOUNT_POINT 2>/dev/null || true; rm -rf $MOUNT_POINT $ROOTFS_TEMP" EXIT

mount "$VM_DIR/rootfs.ext4" "$MOUNT_POINT"
info "Copying files to rootfs image..."
cp -a "$ROOTFS_TEMP/"* "$MOUNT_POINT/"
sync
umount "$MOUNT_POINT"
rm -rf "$MOUNT_POINT"

info "✓ Rootfs image created"

# Create home volume
info "Creating home volume..."
HOME_SIZE_MB=$(numfmt --from=iec "$HOME_SIZE" | awk '{print int($1/1024/1024)}')
dd if=/dev/zero of="$VM_DIR/home.ext4" bs=1M count=$HOME_SIZE_MB status=progress
mkfs.ext4 -F "$VM_DIR/home.ext4"

info "✓ Home volume created"

# Create TAP device
TAP_NAME="tap-$VM_NAME"
info "Creating TAP device $TAP_NAME..."

if ip link show "$TAP_NAME" &>/dev/null; then
    warn "TAP device $TAP_NAME already exists, reusing it"
else
    ip tuntap add "$TAP_NAME" mode tap user "$SUDO_USER"
    ip link set "$TAP_NAME" master "$BRIDGE_NAME"
    ip link set "$TAP_NAME" up
fi

echo "$TAP_NAME" > "$STATE_DIR_VM/tap_name.txt"
info "✓ TAP device created and attached to bridge"

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
