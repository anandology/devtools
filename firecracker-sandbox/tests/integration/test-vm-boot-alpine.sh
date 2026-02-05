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
# Try multiple kernel locations
if [[ -f "/root/.firecracker-vms/.images/vmlinux" ]]; then
    KERNEL="/root/.firecracker-vms/.images/vmlinux"
elif [[ -f "$HOME/.firecracker-vms/.images/vmlinux" ]]; then
    KERNEL="$HOME/.firecracker-vms/.images/vmlinux"
else
    KERNEL="$PROJECT_ROOT/tests/images/vmlinux"
fi

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
CONSOLE_LOG="/tmp/console-$TEST_VM.log"
register_cleanup "rm -f '$CONSOLE_LOG'"

# Start firecracker with timeout and capture output
# Firecracker with --config-file runs in foreground, so we use timeout
timeout 10 firecracker \
    --api-sock "$SOCKET_PATH" \
    --config-file "/tmp/firecracker-config-$TEST_VM.json" \
    > "$CONSOLE_LOG" 2>&1 &

FC_PID=$!
register_cleanup "kill $FC_PID 2>/dev/null || true"

echo ""
echo "Waiting for VM to boot..."
sleep 3

# Check if VM booted successfully by looking for success message in console output
if grep -q "Successfully started microvm" "$CONSOLE_LOG" 2>/dev/null; then
    _print_result "PASS" "Firecracker successfully started microVM" || true
else
    _print_result "FAIL" "Firecracker did not start microVM successfully" || true
    echo "  Console output:"
    cat "$CONSOLE_LOG" | head -20
fi

echo ""
assert_summary
