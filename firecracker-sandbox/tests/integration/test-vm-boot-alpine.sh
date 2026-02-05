#!/bin/bash
# Test Alpine VM boot
# Basic boot test with Alpine rootfs (no network)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

echo "=========================================="
echo "Test: Alpine VM Boot"
echo "=========================================="
echo ""

TEST_VM="test-alpine-boot-$$"
SOCKET_PATH="/tmp/firecracker-$TEST_VM.socket"
ROOTFS="$PROJECT_ROOT/tests/images/alpine-test.ext4"
KERNEL="$PROJECT_ROOT/tests/images/vmlinux"

# Register cleanup
register_cleanup "rm -f '$SOCKET_PATH'"

echo "Checking prerequisites..."
if ! command -v firecracker &>/dev/null; then
    echo "  SKIP: firecracker not found"
    assert_summary
    exit 0
fi

if [[ ! -f "$ROOTFS" ]]; then
    echo "  SKIP: Alpine rootfs not found at $ROOTFS"
    assert_summary
    exit 0
fi

if [[ ! -f "$KERNEL" ]]; then
    echo "  SKIP: Kernel not found at $KERNEL (download from firecracker releases)"
    assert_summary
    exit 0
fi

_print_result "PASS" "All prerequisites present" || true

echo ""
echo "Creating VM configuration..."
cat > "/tmp/firecracker-config-$TEST_VM.json" << EOF
{
  "boot-source": {
    "kernel_image_path": "$KERNEL",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "$ROOTFS",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 128
  }
}
EOF

register_cleanup "rm -f '/tmp/firecracker-config-$TEST_VM.json'"

echo ""
echo "Starting firecracker..."
firecracker --api-sock "$SOCKET_PATH" --config-file "/tmp/firecracker-config-$TEST_VM.json" >/dev/null 2>&1 &
FC_PID=$!
register_cleanup "kill $FC_PID 2>/dev/null || true"

echo ""
echo "Checking firecracker process..."
sleep 2

if ps -p $FC_PID >/dev/null 2>&1; then
    _print_result "PASS" "Firecracker process running" || true
else
    _print_result "FAIL" "Firecracker process exited" || true
fi

echo ""
assert_summary
