#!/bin/bash
# Execute a command or interactive shell inside a chrooted rootfs/home image
#
# This script handles mounting/unmounting of rootfs and optional home images.
# Use --extract to unpack a tgz at the root of the chroot, --copy to copy files
# into the chroot, then run a command or start an interactive shell.
#
# Usage:
#   chroot-image.sh --root rootfs.ext4 [--home home.ext4] [--extract tgz-path] [--copy src:dest ...] [--verbose] [command arg1 arg2 ...]
#
# If a command is given, it is run inside the chroot. If no arguments follow
# the flags, an interactive bash shell is started (useful for copying files
# and exploring).

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
    if [[ -n "${VERBOSE:-}" ]]; then
        echo -e "${GREEN}$1${NC}"
    fi
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

usage() {
    cat << 'EOF'
Usage: sudo ./chroot-image.sh --root <rootfs.ext4> [--home <home.ext4>] [--extract <tgz-path>] [--copy src:dest ...] [--verbose] [command arg1 arg2 ...]

Execute a command or interactive shell inside a chrooted rootfs image.

Arguments:
  --root PATH      Path to rootfs ext4 image (required)
  --home PATH      Path to home ext4 image (optional, will be mounted at /home)
  --extract PATH   Extract this .tgz/.tar.gz at the root of the chroot before running
  --copy SRC:DEST  Copy file SRC from host to DEST inside chroot (may be repeated)
  --verbose        Print progress messages
  -h, --help       Show this help message

  Remaining arguments are the command to run inside the chroot (path + args).
  If no command is given, an interactive bash shell is started.

Examples:
  # Extract Alpine rootfs tgz into empty image, then run a command
  sudo ./chroot-image.sh --root empty.ext4 --extract alpine-minirootfs.tar.gz /bin/sh -c "echo hello"

  # Copy script and run it
  sudo ./chroot-image.sh --root root.ext4 --copy myscript.sh:/tmp/myscript.sh /tmp/myscript.sh arg1 arg2

  # Interactive shell (e.g. to copy files manually or explore)
  sudo ./chroot-image.sh --root root.ext4 --home home.ext4

  # Copy multiple files then run a command
  sudo ./chroot-image.sh --root root.ext4 --copy cfg.ini:/etc/app/cfg.ini --copy run.sh:/tmp/run.sh /tmp/run.sh
EOF
    exit 0
}

# Parse arguments
ROOT_IMAGE=""
HOME_IMAGE=""
EXTRACT_TGZ=""
COPY_PAIRS=()
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --root)
            ROOT_IMAGE="$2"
            shift 2
            ;;
        --home)
            HOME_IMAGE="$2"
            shift 2
            ;;
        --extract)
            [[ $# -ge 2 ]] || error "--extract requires tgz-path"
            EXTRACT_TGZ="$2"
            shift 2
            ;;
        --copy)
            [[ $# -ge 2 ]] || error "--copy requires src:dest"
            COPY_PAIRS+=("$2")
            shift 2
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            # First non-option: rest is command to run in chroot
            break
            ;;
    esac
done
# Remaining "$@" is the command (possibly empty)

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

if [[ -n "$EXTRACT_TGZ" ]] && [[ ! -f "$EXTRACT_TGZ" ]]; then
    error "Extract path not found: $EXTRACT_TGZ"
fi

for pair in "${COPY_PAIRS[@]}"; do
    src="${pair%%:*}"
    if [[ -z "$src" ]] || [[ "$src" == "$pair" ]]; then
        error "Invalid --copy (expected src:dest): $pair"
    fi
    if [[ ! -e "$src" ]]; then
        error "Copy source not found: $src"
    fi
done

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

    sync

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

# Extract tgz at root if requested
if [[ -n "$EXTRACT_TGZ" ]]; then
    info "Extracting $EXTRACT_TGZ into chroot root..."
    tar -xzf "$EXTRACT_TGZ" -C "$MOUNT_POINT"
fi

# Copy files into chroot
for pair in "${COPY_PAIRS[@]}"; do
    src="${pair%%:*}"
    dest="${pair#*:}"
    dest_path="$MOUNT_POINT/$dest"
    mkdir -p "$(dirname "$dest_path")"
    info "Copying into chroot: $src -> $dest"
    cp -ar "$src" "$dest_path"
done

# cd $MOUNT_POINT
# exec /bin/bash

echo "running $*"

# Run command or start interactive shell
if [[ $# -gt 0 ]]; then
    info "Running in chroot: $*"
    chroot "$MOUNT_POINT" "$@"
    EXIT_CODE=$?
    info "Command completed with exit code: $EXIT_CODE"
else
    info "Starting interactive shell in chroot..."
    info "Type 'exit' to leave and unmount images"
    echo ""
    chroot "$MOUNT_POINT" /bin/bash
    EXIT_CODE=$?
fi

exit $EXIT_CODE
