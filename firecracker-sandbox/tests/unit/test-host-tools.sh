#!/bin/bash
# Test host tools
# Verifies that all required tools are installed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"

echo "=========================================="
echo "Testing Host Tools"
echo "=========================================="
echo ""

# List of required tools
REQUIRED_TOOLS=(
    "curl"
    "tar"
    "mkfs.ext4"
    "mount"
    "umount"
    "ip"
    "iptables"
    "firecracker"
    "ssh"
    "nc"
)

# List of optional but recommended tools
OPTIONAL_TOOLS=(
    "docker"
    "debootstrap"
    "screen"
    "tmux"
)

echo "Checking required tools..."
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        _print_result "PASS" "$tool is installed" || true
    else
        _print_result "FAIL" "$tool is not installed" || true
    fi
done

echo ""
echo "Checking optional tools..."
for tool in "${OPTIONAL_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        _print_result "PASS" "$tool is installed (optional)"
    else
        echo "  INFO: $tool is not installed (optional)"
    fi
done

echo ""
echo "Checking firecracker version..."
if command -v firecracker &>/dev/null; then
    FC_VERSION=$(firecracker --version 2>&1 | head -n1 || echo "unknown")
    echo "  Firecracker version: $FC_VERSION"
fi

echo ""
assert_summary
