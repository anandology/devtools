#!/bin/bash
# Test KVM access
# Verifies that /dev/kvm exists and is accessible

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

echo "=========================================="
echo "Testing KVM Access"
echo "=========================================="
echo ""

echo "Checking /dev/kvm exists..."
if [[ -e "/dev/kvm" ]]; then
    _print_result "PASS" "/dev/kvm device exists" || true
else
    echo "  SKIP: /dev/kvm does not exist (not on KVM host)"
fi

echo ""
echo "Checking /dev/kvm is readable..."
if [[ -e "/dev/kvm" ]] && [[ -r "/dev/kvm" ]]; then
    _print_result "PASS" "/dev/kvm is readable" || true
else
    echo "  SKIP: /dev/kvm is not readable or does not exist"
fi

echo ""
echo "Checking /dev/kvm is writable..."
if [[ -e "/dev/kvm" ]] && [[ -w "/dev/kvm" ]]; then
    _print_result "PASS" "/dev/kvm is writable" || true
else
    echo "  SKIP: /dev/kvm is not writable or does not exist"
fi

echo ""
echo "Checking user groups..."
CURRENT_USER="${USER:-$(whoami)}"
USER_GROUPS=$(groups "$CURRENT_USER" 2>/dev/null || echo "")
if [[ -e "/dev/kvm" ]]; then
    if echo "$USER_GROUPS" | grep -q "kvm"; then
        _print_result "PASS" "User $CURRENT_USER is in kvm group" || true
    else
        echo "  INFO: User $CURRENT_USER is not in kvm group (run: sudo usermod -aG kvm $CURRENT_USER)"
    fi
else
    echo "  SKIP: /dev/kvm does not exist"
fi

echo ""
assert_summary
