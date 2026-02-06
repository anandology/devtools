#!/bin/bash
# Test assertion functions
# Usage: source tests/lib/assert.sh
#
# Example:
#   assert_equals "hello" "hello" "strings should match"
#   assert_file_exists "/etc/hosts" "hosts file should exist"
#   assert_success "echo test" "echo should succeed"

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
_ASSERT_PASSED=0
_ASSERT_FAILED=0

# Print test result
_print_result() {
    local status="$1"
    local message="$2"
    
    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        _ASSERT_PASSED=$((_ASSERT_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        _ASSERT_FAILED=$((_ASSERT_FAILED + 1))
    fi
}

# Assert that two values are equal
# Usage: assert_equals <expected> <actual> <message>
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"
    
    if [[ "$expected" == "$actual" ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message (expected: '$expected', actual: '$actual')"
        return 1
    fi
}

# Assert that two values are not equal
# Usage: assert_not_equals <not_expected> <actual> <message>
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Value should not be '$not_expected'}"
    
    if [[ "$not_expected" != "$actual" ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message (both values are '$actual')"
        return 1
    fi
}

# Assert that a command succeeds (exit code 0)
# Usage: assert_success <command> <message>
assert_success() {
    local command="$1"
    local message="${2:-Command should succeed: $command}"
    
    if eval "$command" >/dev/null 2>&1; then
        _print_result "PASS" "$message"
        return 0
    else
        local exit_code=$?
        _print_result "FAIL" "$message (exit code: $exit_code)"
        return 1
    fi
}

# Assert that a command fails (non-zero exit code)
# Usage: assert_failure <command> <message>
assert_failure() {
    local command="$1"
    local message="${2:-Command should fail: $command}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message (command succeeded unexpectedly)"
        return 1
    fi
}

# Assert that a file exists
# Usage: assert_file_exists <path> <message>
assert_file_exists() {
    local path="$1"
    local message="${2:-File should exist: $path}"
    
    if [[ -f "$path" ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message"
        return 1
    fi
}

# Assert that a file does not exist
# Usage: assert_file_not_exists <path> <message>
assert_file_not_exists() {
    local path="$1"
    local message="${2:-File should not exist: $path}"
    
    if [[ ! -f "$path" ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message"
        return 1
    fi
}

# Assert that a directory exists
# Usage: assert_dir_exists <path> <message>
assert_dir_exists() {
    local path="$1"
    local message="${2:-Directory should exist: $path}"
    
    if [[ -d "$path" ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message"
        return 1
    fi
}

# Assert that a string contains a substring
# Usage: assert_contains <haystack> <needle> <message>
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain '$needle'}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message"
        return 1
    fi
}

# Assert that a string does not contain a substring
# Usage: assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain '$needle'}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message"
        return 1
    fi
}

# Assert that a file is executable
# Usage: assert_executable <path> <message>
assert_executable() {
    local path="$1"
    local message="${2:-File should be executable: $path}"
    
    if [[ -x "$path" ]]; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message"
        return 1
    fi
}

# Assert that a bash script has valid syntax
# Usage: assert_valid_bash <path> <message>
assert_valid_bash() {
    local path="$1"
    local message="${2:-Script should have valid bash syntax: $path}"
    
    if bash -n "$path" 2>/dev/null; then
        _print_result "PASS" "$message"
        return 0
    else
        _print_result "FAIL" "$message"
        return 1
    fi
}

# Print test summary
# Usage: assert_summary
assert_summary() {
    local total=$((_ASSERT_PASSED + _ASSERT_FAILED))
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo -e "Total:  $total"
    echo -e "${GREEN}Passed: $_ASSERT_PASSED${NC}"
    echo -e "${RED}Failed: $_ASSERT_FAILED${NC}"
    echo "=========================================="
    
    if [[ $_ASSERT_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}
