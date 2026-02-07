#!/bin/bash
# Mount rootfs/home images and optionally execute a command inside the chroot
#
# This script handles mounting/unmounting of rootfs and optional home images.
# Use --extract to unpack a tgz at the root of the chroot, --copy to copy files
# into the chroot, then optionally run a command. If no command is provided,
# the script will only perform the copy/extract operations and exit.
#
# Usage:
#   chroot-image.sh --root rootfs.ext4 [--home home.ext4] [--extract tgz-path] [--copy src:dest ...] [--import dir-path] [--verbose] [command arg1 arg2 ...]
#
# If a command is given, it is run inside the chroot. If no command is provided,
# the script will only perform mount, extract, and copy operations, then exit.

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
Usage: sudo ./chroot-image.sh --root <rootfs.ext4> [--home <home.ext4>] [--extract <tgz-path>] [--copy src:dest ...] [--import <dir-path>] [--verbose] [command arg1 arg2 ...]

Mount rootfs/home images and optionally execute a command inside the chroot.

Arguments:
  --root PATH      Path to rootfs ext4 image (required)
  --home PATH      Path to home ext4 image (optional, will be mounted at /home)
  --extract PATH   Extract this .tgz/.tar.gz at the root of the chroot
  --copy SRC:DEST  Copy file SRC from host to DEST inside chroot (may be repeated)
  --import PATH    Copy all files from directory PATH into the root of the chroot (preserves permissions)
  --verbose        Print progress messages
  -h, --help       Show this help message

  Remaining arguments are the command to run inside the chroot (path + args).
  If no command is given, the script will only perform mount, extract, and copy
  operations, then exit (useful for just copying files to an image).

Examples:
  # Extract Alpine rootfs tgz into empty image, then run a command
  sudo ./chroot-image.sh --root empty.ext4 --extract alpine-minirootfs.tar.gz /bin/sh -c "echo hello"

  # Copy script and run it
  sudo ./chroot-image.sh --root root.ext4 --copy myscript.sh:/tmp/myscript.sh /tmp/myscript.sh arg1 arg2

  # Just copy files to an image (no command execution)
  sudo ./chroot-image.sh --root root.ext4 --home home.ext4 --copy file1.txt:/tmp/file1.txt --copy file2.txt:/tmp/file2.txt

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
IMPORT_DIR=""
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
        --import)
            [[ $# -ge 2 ]] || error "--import requires dir-path"
            IMPORT_DIR="$2"
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

if [[ -n "$IMPORT_DIR" ]] && [[ ! -d "$IMPORT_DIR" ]]; then
    error "Import directory not found: $IMPORT_DIR"
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

# Import directory into chroot root if requested
if [[ -n "$IMPORT_DIR" ]]; then
    info "Importing directory $IMPORT_DIR into chroot root..."
    # Copy all contents (including hidden files) preserving permissions
    cp -a "$IMPORT_DIR"/. "$MOUNT_POINT/"
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

# Run command if provided
if [[ $# -gt 0 ]]; then
    info "Running in chroot: $*"
    chroot "$MOUNT_POINT" "$@"
    EXIT_CODE=$?
    info "Command completed with exit code: $EXIT_CODE"
    exit $EXIT_CODE
else
    info "No command provided. Mount, extract, and copy operations completed."
    exit 0
fi
