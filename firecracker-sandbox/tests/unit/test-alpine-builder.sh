#!/bin/bash
# Test Alpine rootfs builder script
# This verifies the builder script exists and is well-formed

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test libraries
source "$SCRIPT_DIR/../lib/assert.sh"

echo "=========================================="
echo "Testing Alpine Rootfs Builder"
echo "=========================================="
echo ""

BUILDER_SCRIPT="$PROJECT_ROOT/bin/vm-build/build-alpine-rootfs.sh"

echo "Checking builder script exists..."
assert_file_exists "$BUILDER_SCRIPT" "Alpine builder script should exist" || true

echo ""
echo "Checking builder script is executable..."
if [[ -x "$BUILDER_SCRIPT" ]]; then
    _print_result "PASS" "Builder script is executable"
else
    _print_result "FAIL" "Builder script is not executable"
fi

echo ""
echo "Checking builder script syntax..."
if bash -n "$BUILDER_SCRIPT" 2>/dev/null; then
    _print_result "PASS" "Builder script syntax is valid"
else
    _print_result "FAIL" "Builder script has syntax errors"
fi

echo ""
echo "Checking builder script has required components..."
assert_contains "$(cat "$BUILDER_SCRIPT")" "alpine-minirootfs" "Script should download Alpine minirootfs" || true
assert_contains "$(cat "$BUILDER_SCRIPT")" "172.16.0.2" "Script should configure test IP" || true
assert_contains "$(cat "$BUILDER_SCRIPT")" "openssh" "Script should install OpenSSH" || true
assert_contains "$(cat "$BUILDER_SCRIPT")" "mkfs.ext4" "Script should create ext4 filesystem" || true

echo ""
echo "Checking output directory structure..."
mkdir -p "$PROJECT_ROOT/tests/images"
assert_dir_exists "$PROJECT_ROOT/tests/images" "Test images directory should exist" || true

echo ""
assert_summary
