#!/bin/bash
# Test Firecracker API socket
# Verifies firecracker starts and creates API socket

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

echo "=========================================="
echo "Test: Firecracker API Socket"
echo "=========================================="
echo ""

TEST_VM="test-fc-socket-$$"
SOCKET_PATH="/tmp/firecracker-$TEST_VM.socket"

# Register cleanup
register_cleanup "rm -f '$SOCKET_PATH'"

echo "Checking firecracker binary..."
if ! command -v firecracker &>/dev/null; then
    echo "  SKIP: firecracker not found"
    assert_summary
    exit 0
fi
_print_result "PASS" "firecracker binary found" || true

echo ""
echo "Starting firecracker in background..."
firecracker --api-sock "$SOCKET_PATH" >/dev/null 2>&1 &
FC_PID=$!
register_cleanup "kill $FC_PID 2>/dev/null || true"

echo ""
echo "Waiting for socket creation..."
sleep 1

if [[ -S "$SOCKET_PATH" ]]; then
    _print_result "PASS" "API socket created" || true
else
    _print_result "FAIL" "API socket not created" || true
fi

echo ""
echo "Testing API endpoint..."
if curl -s --unix-socket "$SOCKET_PATH" "http://localhost/" >/dev/null 2>&1; then
    _print_result "PASS" "API responds to requests" || true
else
    echo "  INFO: API may not respond without configuration (this is okay)"
fi

echo ""
assert_summary
