#!/bin/bash
# Test IP forwarding
# Verifies that IP forwarding is enabled or can be enabled

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

echo "=========================================="
echo "Testing IP Forwarding"
echo "=========================================="
echo ""

IP_FORWARD_FILE="/proc/sys/net/ipv4/ip_forward"

echo "Checking IP forward file exists..."
assert_file_exists "$IP_FORWARD_FILE" "IP forward sysctl file should exist" || true

echo ""
echo "Checking current IP forwarding status..."
CURRENT_VALUE=$(cat "$IP_FORWARD_FILE" 2>/dev/null || echo "0")
if [[ "$CURRENT_VALUE" == "1" ]]; then
    _print_result "PASS" "IP forwarding is enabled"
else
    echo "  INFO: IP forwarding is disabled (current value: $CURRENT_VALUE)"
    echo "  INFO: Enable with: sudo sysctl -w net.ipv4.ip_forward=1"
fi

echo ""
echo "Checking if we can modify IP forwarding..."
if [[ -w "$IP_FORWARD_FILE" ]]; then
    _print_result "PASS" "Can modify IP forwarding (running as root)"
else
    echo "  INFO: Cannot modify IP forwarding (need sudo)"
    echo "  INFO: This is expected when not running as root"
fi

echo ""
echo "Checking sysctl availability..."
if command -v sysctl &>/dev/null; then
    _print_result "PASS" "sysctl command is available"
    
    SYSCTL_VALUE=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "unknown")
    echo "  Current value via sysctl: $SYSCTL_VALUE"
else
    _print_result "FAIL" "sysctl command not found"
fi

echo ""
echo "Checking for persistent IP forwarding configuration..."
SYSCTL_CONF="/etc/sysctl.conf"
if [[ -f "$SYSCTL_CONF" ]]; then
    if grep -q "net.ipv4.ip_forward.*=.*1" "$SYSCTL_CONF"; then
        _print_result "PASS" "IP forwarding is configured persistently in $SYSCTL_CONF"
    else
        echo "  INFO: IP forwarding not configured persistently"
        echo "  INFO: Add to $SYSCTL_CONF: net.ipv4.ip_forward=1"
    fi
fi

echo ""
assert_summary
