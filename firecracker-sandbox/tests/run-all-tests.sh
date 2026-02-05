#!/bin/bash
# Master test runner - Runs complete test suite
# Unit tests → Fast integration tests → Production integration tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Timing
START_TIME=$(date +%s)

# Print banner
print_banner() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "$1"
    echo -e "==========================================${NC}"
    echo ""
}

# Print section
print_section() {
    echo ""
    echo -e "${CYAN}>>> $1${NC}"
    echo ""
}

# Run a test script and track results
run_test() {
    local test_script="$1"
    local test_name=$(basename "$test_script" .sh)
    
    echo -e "${BOLD}Running: $test_name${NC}"
    echo ""
    
    ((TOTAL_TESTS++))
    
    if [[ ! -f "$test_script" ]]; then
        echo -e "${YELLOW}SKIP: Test not found${NC}"
        ((SKIPPED_TESTS++))
        return 0
    fi
    
    if [[ ! -x "$test_script" ]]; then
        chmod +x "$test_script"
    fi
    
    local test_output
    local test_exit_code
    
    # Run test and capture output
    if test_output=$("$test_script" 2>&1); then
        test_exit_code=0
    else
        test_exit_code=$?
    fi
    
    # Show output
    echo "$test_output"
    
    # Check result
    if [[ $test_exit_code -eq 0 ]]; then
        if echo "$test_output" | grep -q "SKIP:"; then
            echo -e "${YELLOW}✓ SKIPPED${NC}"
            ((SKIPPED_TESTS++))
        else
            echo -e "${GREEN}✓ PASSED${NC}"
            ((PASSED_TESTS++))
        fi
    else
        echo -e "${RED}✗ FAILED (exit code: $test_exit_code)${NC}"
        ((FAILED_TESTS++))
    fi
    
    echo ""
    echo "===================="
    echo ""
}

# Print usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Run the complete Firecracker VM test suite.

OPTIONS:
    --fast          Run only unit and fast integration tests (skip Ubuntu)
    --unit-only     Run only unit tests
    --integration   Run only integration tests
    --help          Show this help message

EXAMPLES:
    # Run complete test suite
    ./tests/run-all-tests.sh

    # Quick feedback (unit + fast tests)
    ./tests/run-all-tests.sh --fast

    # Unit tests only
    ./tests/run-all-tests.sh --unit-only

    # Integration tests only
    ./tests/run-all-tests.sh --integration
EOF
}

# Parse arguments
RUN_UNIT=true
RUN_FAST=true
RUN_PRODUCTION=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --fast)
            RUN_PRODUCTION=false
            shift
            ;;
        --unit-only)
            RUN_FAST=false
            RUN_PRODUCTION=false
            shift
            ;;
        --integration)
            RUN_UNIT=false
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main test execution
print_banner "Firecracker VM Test Suite"

echo "Test configuration:"
echo "  Unit tests: $([ "$RUN_UNIT" = true ] && echo "✓" || echo "✗")"
echo "  Fast integration: $([ "$RUN_FAST" = true ] && echo "✓" || echo "✗")"
echo "  Production integration: $([ "$RUN_PRODUCTION" = true ] && echo "✓" || echo "✗")"
echo ""

# Check prerequisites
print_section "Checking Prerequisites"

if ! command -v firecracker &>/dev/null; then
    echo -e "${RED}Error: firecracker not found${NC}"
    echo "Install firecracker first"
    exit 1
fi

echo "✓ Firecracker: $(firecracker --version 2>/dev/null | head -n 1 || echo "unknown version")"

if [[ ! -d "$HOME/.firecracker-vms/.images" ]]; then
    echo -e "${YELLOW}Warning: Kernel images directory not found${NC}"
    echo "Run: bin/setup.sh"
fi

echo ""

# Phase 1: Unit Tests
if [[ "$RUN_UNIT" == true ]]; then
    print_banner "Phase 1: Unit Tests (Host Prerequisites)"
    
    print_section "Host Environment Tests"
    run_test "$SCRIPT_DIR/unit/test-kvm-access.sh"
    run_test "$SCRIPT_DIR/unit/test-host-tools.sh"
    
    print_section "Network Setup Tests"
    run_test "$SCRIPT_DIR/unit/test-tap-create.sh"
    run_test "$SCRIPT_DIR/unit/test-tap-ip.sh"
    run_test "$SCRIPT_DIR/unit/test-ip-forward.sh"
    run_test "$SCRIPT_DIR/unit/test-nat-rules.sh"
    
    print_section "Build System Tests"
    run_test "$SCRIPT_DIR/unit/test-alpine-builder.sh"
fi

# Phase 2: Fast Integration Tests
if [[ "$RUN_FAST" == true ]]; then
    print_banner "Phase 2: Fast Integration Tests (Alpine)"
    
    print_section "VM Boot Tests"
    run_test "$SCRIPT_DIR/integration/test-firecracker-socket.sh"
    run_test "$SCRIPT_DIR/integration/test-vm-boot-alpine.sh"
    
    print_section "Network Tests"
    run_test "$SCRIPT_DIR/integration/test-host-to-guest.sh"
    
    print_section "Multi-VM Tests"
    run_test "$SCRIPT_DIR/integration/test-multiple-vms.sh"
fi

# Phase 3: Production Integration Tests
if [[ "$RUN_PRODUCTION" == true ]]; then
    print_banner "Phase 3: Production Integration Tests (Ubuntu)"
    
    print_section "Full Lifecycle Test"
    echo -e "${YELLOW}Note: This test takes 3-5 minutes (builds Ubuntu VM)${NC}"
    echo ""
    run_test "$SCRIPT_DIR/integration/test-full-lifecycle.sh"
fi

# Calculate timing
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

# Print summary
print_banner "Test Summary"

echo "Total tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
echo -e "${RED}Failed:       $FAILED_TESTS${NC}"
echo -e "${YELLOW}Skipped:      $SKIPPED_TESTS${NC}"
echo ""
echo "Total time:   ${MINUTES}m ${SECONDS}s"
echo ""

# Calculate success rate
if [[ $TOTAL_TESTS -gt 0 ]]; then
    COMPLETED=$((TOTAL_TESTS - SKIPPED_TESTS))
    if [[ $COMPLETED -gt 0 ]]; then
        SUCCESS_RATE=$(( (PASSED_TESTS * 100) / COMPLETED ))
        echo "Success rate: ${SUCCESS_RATE}% (of completed tests)"
        echo ""
    fi
fi

# Performance targets
echo "Performance targets:"
if [[ "$RUN_UNIT" == true ]] && [[ "$RUN_FAST" == false ]] && [[ "$RUN_PRODUCTION" == false ]]; then
    echo "  Unit tests only: <30s (actual: ${TOTAL_TIME}s)"
elif [[ "$RUN_PRODUCTION" == false ]]; then
    echo "  Unit + Fast: <60s (actual: ${TOTAL_TIME}s)"
else
    echo "  Full suite: <5m (actual: ${MINUTES}m ${SECONDS}s)"
fi
echo ""

# Exit status
if [[ $FAILED_TESTS -eq 0 ]]; then
    if [[ $PASSED_TESTS -eq 0 ]]; then
        echo -e "${YELLOW}All tests skipped!${NC}"
        echo ""
        echo "Possible reasons:"
        echo "  - Prerequisites not met (run: bin/setup.sh)"
        echo "  - Firecracker not installed"
        echo "  - Test images not built"
        exit 2
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
else
    echo -e "${RED}Some tests failed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  - Check test output above for details"
    echo "  - Review console logs in ~/.firecracker-vms/*/state/console.log"
    echo "  - Run individual tests for debugging"
    exit 1
fi
