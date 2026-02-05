#!/bin/bash
# Run tests in Docker container with KVM support
# Usage: ./run-tests.sh [test_script]
#
# Examples:
#   ./run-tests.sh                    # Run quick-check (all unit tests)
#   ./run-tests.sh tests/quick-check.sh
#   ./run-tests.sh tests/unit/test-kvm-access.sh

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Check Docker availability
if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Install Docker to run tests."
fi

if ! docker info &>/dev/null; then
    error "Docker daemon is not running or not accessible."
fi

# Check for KVM device
if [[ ! -e /dev/kvm ]]; then
    warn "Warning: /dev/kvm not found. KVM-dependent tests will be skipped."
    KVM_DEVICE=""
else
    KVM_DEVICE="--device=/dev/kvm"
fi

# Image name
IMAGE_NAME="firecracker-sandbox-test"
DOCKERFILE="$SCRIPT_DIR/Dockerfile"

# Build Docker image if needed
info "Checking Docker image..."
if ! docker images | grep -q "$IMAGE_NAME"; then
    info "Building Docker image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$SCRIPT_DIR"
else
    # Check if Dockerfile was modified
    IMAGE_DATE=$(docker inspect -f '{{ .Created }}' "$IMAGE_NAME" 2>/dev/null || echo "1970-01-01")
    DOCKERFILE_DATE=$(stat -c %Y "$DOCKERFILE" 2>/dev/null || stat -f %m "$DOCKERFILE" 2>/dev/null || echo "0")
    IMAGE_TIMESTAMP=$(date -d "$IMAGE_DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$IMAGE_DATE" +%s 2>/dev/null || echo "0")
    
    if [[ $DOCKERFILE_DATE -gt $IMAGE_TIMESTAMP ]]; then
        info "Dockerfile modified, rebuilding image..."
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$SCRIPT_DIR"
    else
        info "✓ Docker image up to date"
    fi
fi

# Determine what to run
TEST_CMD="${1:-tests/quick-check.sh}"

# Run tests in Docker
info "Running tests in Docker container..."
echo ""

# Run with privileges needed for networking and KVM
docker run --rm \
    --privileged \
    $KVM_DEVICE \
    -v "$PROJECT_ROOT:/workspace" \
    -w /workspace \
    "$IMAGE_NAME" \
    bash -c "cd /workspace && $TEST_CMD"

EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    info "✓ Tests completed successfully"
else
    error "✗ Tests failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
