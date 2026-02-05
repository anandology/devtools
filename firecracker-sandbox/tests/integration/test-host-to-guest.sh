#!/bin/bash
# Test host to guest connectivity
# Boots Alpine VM with network and pings from host

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

echo "=========================================="
echo "Test: Host to Guest Connectivity"
echo "=========================================="
echo ""

TEST_VM="test-h2g-$$"
TAP_NAME="tap-test-$$"
SOCKET_PATH="/tmp/firecracker-$TEST_VM.socket"
ROOTFS="$PROJECT_ROOT/tests/images/alpine-test.ext4"
KERNEL="$PROJECT_ROOT/tests/images/vmlinux"
GUEST_IP="172.16.0.2"
HOST_IP="172.16.0.1"

# Register cleanup
register_cleanup "rm -f '$SOCKET_PATH'"
register_cleanup "ip link delete '$TAP_NAME' 2>/dev/null || true"

echo "Checking prerequisites..."
if ! command -v firecracker &>/dev/null; then
    echo "  SKIP: firecracker not found"
    assert_summary
    exit 0
fi

if [[ ! -f "$ROOTFS" ]] || [[ ! -f "$KERNEL" ]]; then
    echo "  SKIP: Missing rootfs or kernel"
    assert_summary
    exit 0
fi

echo ""
echo "Creating TAP device..."
if ip tuntap add dev "$TAP_NAME" mode tap 2>/dev/null; then
    _print_result "PASS" "TAP device created" || true
else
    echo "  SKIP: Cannot create TAP device (need root)"
    assert_summary
    exit 0
fi

ip addr add "$HOST_IP/24" dev "$TAP_NAME"
ip link set dev "$TAP_NAME" up

echo ""
echo "Creating VM configuration with network..."
cat > "/tmp/firecracker-config-$TEST_VM.json" << EOF
{
  "boot-source": {
    "kernel_image_path": "$KERNEL",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off ip=$GUEST_IP::$HOST_IP:255.255.255.0::eth0:off"
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

register_cleanup "rm -f '/tmp/firecracker-config-$TEST_VM.json'"

echo ""
echo "Starting VM..."
firecracker --api-sock "$SOCKET_PATH" --config-file "/tmp/firecracker-config-$TEST_VM.json" >/dev/null 2>&1 &
FC_PID=$!
register_cleanup "kill $FC_PID 2>/dev/null || true"

echo ""
echo "Waiting for VM to boot..."
sleep 5

echo ""
echo "Testing ping to guest ($GUEST_IP)..."
if ping -c 3 -W 2 "$GUEST_IP" >/dev/null 2>&1; then
    _print_result "PASS" "Can ping guest from host" || true
else
    _print_result "FAIL" "Cannot ping guest from host" || true
fi

echo ""
assert_summary
