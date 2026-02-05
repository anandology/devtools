#!/bin/bash
# Verification test for test infrastructure
# This tests the test library itself

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test libraries
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

echo "=========================================="
echo "Testing Test Infrastructure"
echo "=========================================="
echo ""

# Test assert.sh functions
echo "Testing assert_equals..."
assert_equals "hello" "hello" "String equality test" || true

echo ""
echo "Testing assert_not_equals..."
assert_not_equals "hello" "world" "String inequality test" || true

echo ""
echo "Testing assert_success..."
assert_success "true" "True command should succeed" || true

echo ""
echo "Testing assert_failure..."
assert_failure "false" "False command should fail" || true

echo ""
echo "Testing assert_file_exists..."
assert_file_exists "$SCRIPT_DIR/lib/assert.sh" "assert.sh should exist" || true

echo ""
echo "Testing assert_file_not_exists..."
assert_file_not_exists "/tmp/nonexistent-file-12345" "Non-existent file test" || true

echo ""
echo "Testing assert_dir_exists..."
assert_dir_exists "$SCRIPT_DIR/lib" "lib directory should exist" || true

echo ""
echo "Testing assert_contains..."
assert_contains "hello world" "world" "String contains test" || true

echo ""
echo "Testing assert_not_contains..."
assert_not_contains "hello world" "foo" "String not contains test" || true

echo ""
echo "Testing cleanup registration..."
TEST_FILE="/tmp/test-cleanup-$$"
echo "test" > "$TEST_FILE"
register_cleanup "cleanup_file '$TEST_FILE'"
assert_file_exists "$TEST_FILE" "Test file created for cleanup test"

echo ""
assert_summary
