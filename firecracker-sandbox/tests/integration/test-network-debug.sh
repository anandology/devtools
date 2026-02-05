#!/bin/bash
# Debug network connectivity issues
# This test boots a VM and captures console output to debug network setup

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=========================================="
echo "Network Debug Test"
echo "=========================================="
echo ""

TEST_VM="test-netdebug-$$"
TAP_NAME="tap-debug-$$"
SOCKET_PATH="/tmp/firecracker-$TEST_VM.socket"
CONSOLE_LOG="/tmp/console-$TEST_VM.log"
ROOTFS="$PROJECT_ROOT/tests/images/alpine-test.ext4"
KERNEL="/root/.firecracker-vms/.images/vmlinux"
GUEST_IP="172.16.0.2"
HOST_IP="172.16.0.1"

# Cleanup
cleanup() {
    echo ""
    echo "Cleaning up..."
    kill $(jobs -p) 2>/dev/null || true
    rm -f "$SOCKET_PATH" "$CONSOLE_LOG"
    ip link delete "$TAP_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "Creating TAP device..."
if ! ip tuntap add dev "$TAP_NAME" mode tap 2>/dev/null; then
    echo "SKIP: Cannot create TAP device (need root)"
    exit 0
fi

ip addr add "$HOST_IP/24" dev "$TAP_NAME"
ip link set dev "$TAP_NAME" up

echo "TAP device created: $TAP_NAME"
ip addr show "$TAP_NAME"
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
  },
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "AA:FC:00:00:00:01",
      "host_dev_name": "$TAP_NAME"
    }
  ]
}
EOF

echo ""
echo "Starting VM with console logging..."
echo "Console output will be saved to: $CONSOLE_LOG"
echo ""

# Start firecracker with console output
timeout 15 firecracker \
    --api-sock "$SOCKET_PATH" \
    --config-file "/tmp/firecracker-config-$TEST_VM.json" \
    > "$CONSOLE_LOG" 2>&1 &

FC_PID=$!

echo "Firecracker PID: $FC_PID"
echo "Waiting 12 seconds for boot and init..."
sleep 12

echo ""
echo "=========================================="
echo "Console Output:"
echo "=========================================="
cat "$CONSOLE_LOG" || echo "No console output captured"

echo ""
echo "=========================================="
echo "Network State on Host:"
echo "=========================================="
echo "TAP device:"
ip addr show "$TAP_NAME"
echo ""
echo "Route table:"
ip route show
echo ""
echo "ARP table:"
ip neigh show

echo ""
echo "=========================================="
echo "Testing connectivity:"
echo "=========================================="
echo "Pinging guest ($GUEST_IP)..."
if ping -c 3 -W 2 "$GUEST_IP"; then
    echo "SUCCESS: Can ping guest!"
else
    echo "FAILED: Cannot ping guest"
fi

# Keep firecracker running a bit longer to see console output
sleep 2
