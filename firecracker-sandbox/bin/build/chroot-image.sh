#!/bin/bash
# Execute a script or interactive shell inside a chrooted rootfs/home image
#
# This script handles mounting/unmounting of rootfs and optional home images,
# then either executes a script or drops into an interactive shell.
#
# Usage:
#   chroot-image.sh --root rootfs.ext4 [--home home.ext4] [--script script.sh]
#
# If --script is provided, the script will be copied to /tmp/script.sh in the
# chroot and executed. If --script is omitted, an interactive bash shell will
# be started in the chroot.

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
Usage: sudo ./chroot-image.sh --root <rootfs.ext4> [--home <home.ext4>] [--script <script.sh>]

Execute a script or interactive shell inside a chrooted rootfs image.

Arguments:
  --root PATH      Path to rootfs ext4 image (required)
  --home PATH      Path to home ext4 image (optional, will be mounted at /home)
  --script PATH    Path to script to execute inside chroot (optional)
  -h, --help       Show this help message

If --script is provided:
  1. Script will be copied to /tmp/script.sh in the chroot
  2. Made executable
  3. Executed with bash
  4. Exit status of the script will be returned

If --script is omitted:
  An interactive bash shell will be started in the chroot.
  Type 'exit' to leave the shell and unmount the images.

Examples:
  # Execute script in rootfs only
  sudo ./chroot-image.sh --root rootfs.ext4 --script configure.sh

  # Execute script with home volume mounted
  sudo ./chroot-image.sh --root rootfs.ext4 --home home.ext4 --script setup-user.sh

  # Interactive shell for manual configuration
  sudo ./chroot-image.sh --root rootfs.ext4 --home home.ext4
EOF
    exit 0
}

# Parse arguments
ROOT_IMAGE=""
HOME_IMAGE=""
SCRIPT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --root)
            ROOT_IMAGE="$2"
            shift 2
            ;;
        --home)
            HOME_IMAGE="$2"
            shift 2
            ;;
        --script)
            SCRIPT_PATH="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate arguments
if [[ -z "$ROOT_IMAGE" ]]; then
    error "--root is required"
fi

if [[ ! -f "$ROOT_IMAGE" ]]; then
    error "Root image not found: $ROOT_IMAGE"
fi

if [[ -n "$HOME_IMAGE" ]] && [[ ! -f "$HOME_IMAGE" ]]; then
    error "Home image not found: $HOME_IMAGE"
fi

if [[ -n "$SCRIPT_PATH" ]] && [[ ! -f "$SCRIPT_PATH" ]]; then
    error "Script not found: $SCRIPT_PATH"
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo"
fi

# Create temporary mount point
MOUNT_POINT=$(mktemp -d)
HOME_MOUNT=""

# Cleanup function
cleanup() {
    local exit_code=$?

    # Unmount home if mounted
    if [[ -n "$HOME_MOUNT" ]] && mountpoint -q "$HOME_MOUNT" 2>/dev/null; then
        umount "$HOME_MOUNT" 2>/dev/null || true
        rmdir "$HOME_MOUNT" 2>/dev/null || true
    fi

    # Unmount root if mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        umount "$MOUNT_POINT" 2>/dev/null || true
    fi

    # Remove mount point
    rmdir "$MOUNT_POINT" 2>/dev/null || true

    return $exit_code
}

trap cleanup EXIT

# Mount root image
info "Mounting root image: $ROOT_IMAGE"
mount "$ROOT_IMAGE" "$MOUNT_POINT"

# Mount home image if provided
if [[ -n "$HOME_IMAGE" ]]; then
    HOME_MOUNT="$MOUNT_POINT/home"
    mkdir -p "$HOME_MOUNT"
    info "Mounting home image: $HOME_IMAGE"
    mount "$HOME_IMAGE" "$HOME_MOUNT"
fi

# Execute script or start interactive shell
if [[ -n "$SCRIPT_PATH" ]]; then
    # Copy script into chroot
    SCRIPT_IN_CHROOT="$MOUNT_POINT/tmp/script.sh"
    info "Copying script to chroot: $SCRIPT_PATH -> /tmp/script.sh"
    cp "$SCRIPT_PATH" "$SCRIPT_IN_CHROOT"
    chmod +x "$SCRIPT_IN_CHROOT"
    
    # Execute script in chroot
    info "Executing script in chroot..."
    chroot "$MOUNT_POINT" /bin/bash /tmp/script.sh
    EXIT_CODE=$?
    
    # Cleanup will happen via trap
    info "Script completed with exit code: $EXIT_CODE"
else
    # Start interactive shell
    info "Starting interactive shell in chroot..."
    info "Type 'exit' to leave and unmount images"
    echo ""
    chroot "$MOUNT_POINT" /bin/bash
    EXIT_CODE=$?
fi

exit $EXIT_CODE
