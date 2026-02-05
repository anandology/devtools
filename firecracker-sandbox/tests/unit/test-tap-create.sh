#!/bin/bash
# Test TAP device creation
# Creates a test TAP device and verifies it

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

echo "=========================================="
echo "Testing TAP Device Creation"
echo "=========================================="
echo ""

TAP_NAME="tap-test-$$"

# Register cleanup
register_cleanup "cleanup_tap_device '$TAP_NAME'"

echo "Checking if we can create TAP devices..."
if sudo -n ip tuntap add dev "$TAP_NAME" mode tap 2>/dev/null; then
    _print_result "PASS" "TAP device created: $TAP_NAME" || true
else
    echo "  SKIP: Cannot create TAP device without sudo (this test requires sudo)"
    echo ""
    assert_summary
    exit 0
fi

echo ""
echo "Verifying TAP device exists..."
if ip link show "$TAP_NAME" &>/dev/null; then
    _print_result "PASS" "TAP device $TAP_NAME is visible in ip link"
else
    _print_result "FAIL" "TAP device $TAP_NAME not found in ip link"
fi

echo ""
echo "Checking TAP device is down..."
TAP_STATE=$(ip link show "$TAP_NAME" | grep -o 'state [A-Z]*' | awk '{print $2}')
if [[ "$TAP_STATE" == "DOWN" ]]; then
    _print_result "PASS" "TAP device is in DOWN state"
else
    echo "  INFO: TAP device is in $TAP_STATE state"
fi

echo ""
echo "Bringing TAP device up..."
if sudo ip link set dev "$TAP_NAME" up 2>/dev/null; then
    _print_result "PASS" "TAP device brought up successfully"
else
    _print_result "FAIL" "Failed to bring TAP device up"
fi

echo ""
echo "Verifying TAP device is up..."
TAP_INFO=$(ip link show "$TAP_NAME")
TAP_STATE=$(echo "$TAP_INFO" | grep -o 'state [A-Z]*' | awk '{print $2}')
TAP_FLAGS=$(echo "$TAP_INFO" | grep -oP '<[^>]+>')

# TAP device is considered up if:
# 1. State is UP or UNKNOWN (has carrier)
# 2. State is DOWN but has UP flag (no carrier, which is expected for disconnected TAP)
if [[ "$TAP_STATE" == "UP" ]] || [[ "$TAP_STATE" == "UNKNOWN" ]]; then
    _print_result "PASS" "TAP device is in UP/UNKNOWN state"
elif [[ "$TAP_STATE" == "DOWN" ]] && [[ "$TAP_FLAGS" == *"UP"* ]]; then
    _print_result "PASS" "TAP device has UP flag (state DOWN due to no carrier, which is normal)"
else
    _print_result "FAIL" "TAP device is in $TAP_STATE state without UP flag"
fi

echo ""
assert_summary

# Cleanup happens automatically via trap
