#!/bin/bash
# Test TAP IP configuration
# Creates a TAP device, assigns IP, and verifies connectivity

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

echo "=========================================="
echo "Testing TAP IP Configuration"
echo "=========================================="
echo ""

TAP_NAME="tap-test-$$"
TAP_IP="192.168.99.1"
TAP_CIDR="$TAP_IP/24"

# Register cleanup
register_cleanup "cleanup_tap_device '$TAP_NAME'"

echo "Creating TAP device..."
if sudo -n ip tuntap add dev "$TAP_NAME" mode tap 2>/dev/null; then
    _print_result "PASS" "TAP device created" || true
else
    echo "  SKIP: Cannot create TAP device without sudo (this test requires sudo)"
    echo ""
    assert_summary
    exit 0
fi

echo ""
echo "Assigning IP address $TAP_CIDR..."
if sudo ip addr add "$TAP_CIDR" dev "$TAP_NAME" 2>/dev/null; then
    _print_result "PASS" "IP address assigned"
else
    _print_result "FAIL" "Failed to assign IP address"
fi

echo ""
echo "Bringing TAP device up..."
if sudo ip link set dev "$TAP_NAME" up 2>/dev/null; then
    _print_result "PASS" "TAP device brought up"
else
    _print_result "FAIL" "Failed to bring TAP device up"
fi

echo ""
echo "Verifying IP address assignment..."
if ip addr show "$TAP_NAME" | grep -q "$TAP_IP"; then
    _print_result "PASS" "IP address $TAP_IP is assigned to $TAP_NAME"
else
    _print_result "FAIL" "IP address $TAP_IP not found on $TAP_NAME"
fi

echo ""
echo "Verifying routing table..."
if ip route | grep -q "$TAP_NAME"; then
    _print_result "PASS" "Route entry exists for $TAP_NAME"
else
    _print_result "FAIL" "No route entry for $TAP_NAME"
fi

echo ""
echo "Testing ping to TAP interface..."
if ping -c 1 -W 2 "$TAP_IP" &>/dev/null; then
    _print_result "PASS" "Can ping TAP interface at $TAP_IP"
else
    _print_result "FAIL" "Cannot ping TAP interface at $TAP_IP"
fi

echo ""
assert_summary

# Cleanup happens automatically via trap
