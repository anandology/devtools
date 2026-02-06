#!/bin/bash
# Create an empty ext4 filesystem image
#
# Usage:
#   make-image.sh --size 8G --path rootfs.ext4

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
Usage: sudo ./make-image.sh --size <SIZE> --path <PATH>

Create an empty ext4 filesystem image.

Arguments:
  --size SIZE      Size of the image (e.g., 8G, 2048M, 2G)
  --path PATH      Path to output ext4 image file
  -h, --help       Show this help message

Examples:
    ./make-image.sh --size 8G --path rootfs.ext4
    ./make-image.sh --size 2048M --path /tmp/home.ext4
EOF
    exit 0
}

# Parse arguments
IMAGE_SIZE=""
IMAGE_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --size)
            IMAGE_SIZE="$2"
            shift 2
            ;;
        --path)
            IMAGE_PATH="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate arguments
if [[ -z "$IMAGE_SIZE" ]]; then
    error "--size is required"
fi

if [[ -z "$IMAGE_PATH" ]]; then
    error "--path is required"
fi

# Check for required tools
if ! command -v mkfs.ext4 &> /dev/null; then
    error "mkfs.ext4 is not installed. Install with: sudo apt install e2fsprogs"
fi

# Check if output path already exists
if [[ -f "$IMAGE_PATH" ]]; then
    error "Image already exists: $IMAGE_PATH (remove it first if you want to recreate)"
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$IMAGE_PATH")
if [[ ! -d "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
fi

# Create the image
info "Creating ext4 image: $IMAGE_PATH"
info "  Size: $IMAGE_SIZE"

dd if=/dev/zero of="$IMAGE_PATH" bs=1 count=0 seek="$IMAGE_SIZE" status=progress
mkfs.ext4 -F "$IMAGE_PATH"


# Get actual file size
ACTUAL_SIZE=$(du -h "$IMAGE_PATH" | cut -f1)

info ""
info "========================================="
info "  Image created successfully"
info "========================================="
info "Path: $IMAGE_PATH"
info "Actual Size: $ACTUAL_SIZE"
info ""
