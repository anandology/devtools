#!/bin/bash
# Test NAT/MASQUERADE rules
# Verifies iptables NAT configuration

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

echo "=========================================="
echo "Testing NAT/MASQUERADE Rules"
echo "=========================================="
echo ""

echo "Checking iptables availability..."
if command -v iptables &>/dev/null; then
    _print_result "PASS" "iptables command is available" || true
else
    echo "  SKIP: iptables command not found"
    assert_summary
    exit 0
fi

echo ""
echo "Checking iptables NAT table access..."
if sudo -n iptables -t nat -L -n &>/dev/null; then
    _print_result "PASS" "Can access iptables NAT table" || true
else
    echo "  SKIP: Cannot access iptables NAT table without sudo (this test requires sudo)"
    echo ""
    assert_summary
    exit 0
fi

echo ""
echo "Checking current NAT rules..."
NAT_RULES=$(sudo iptables -t nat -L POSTROUTING -n 2>/dev/null || echo "")
if [[ -n "$NAT_RULES" ]]; then
    _print_result "PASS" "NAT POSTROUTING chain exists"
    
    if echo "$NAT_RULES" | grep -q "MASQUERADE"; then
        echo "  INFO: MASQUERADE rules found"
    else
        echo "  INFO: No MASQUERADE rules found"
    fi
else
    _print_result "FAIL" "Cannot read NAT POSTROUTING chain"
fi

echo ""
echo "Checking iptables FORWARD chain..."
if sudo iptables -L FORWARD -n &>/dev/null; then
    _print_result "PASS" "Can access FORWARD chain"
    
    FORWARD_POLICY=$(sudo iptables -L FORWARD -n | grep "Chain FORWARD" | grep -o "policy [A-Z]*" | awk '{print $2}')
    echo "  Current FORWARD policy: $FORWARD_POLICY"
    
    if [[ "$FORWARD_POLICY" == "ACCEPT" ]]; then
        echo "  INFO: FORWARD policy is ACCEPT (allows forwarding)"
    else
        echo "  INFO: FORWARD policy is $FORWARD_POLICY (may need rules to allow forwarding)"
    fi
else
    _print_result "FAIL" "Cannot access FORWARD chain"
fi

echo ""
echo "Checking if we can add test NAT rule..."
TEST_COMMENT="test-nat-rule-$$"
if sudo iptables -t nat -A POSTROUTING -j MASQUERADE -m comment --comment "$TEST_COMMENT" 2>/dev/null; then
    _print_result "PASS" "Can add NAT MASQUERADE rule"
    
    # Clean up test rule
    sudo iptables -t nat -D POSTROUTING -j MASQUERADE -m comment --comment "$TEST_COMMENT" 2>/dev/null || true
else
    _print_result "FAIL" "Cannot add NAT MASQUERADE rule (need sudo and appropriate kernel modules)"
fi

echo ""
echo "Checking for default gateway..."
if ip route | grep -q "default"; then
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    _print_result "PASS" "Default gateway exists (interface: $DEFAULT_INTERFACE)"
else
    _print_result "FAIL" "No default gateway found"
fi

echo ""
assert_summary
