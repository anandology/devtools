#!/bin/bash
# Quick check - runs all unit tests
# Fast feedback loop for development (no VM builds or boots)
# Target: Complete in <15 seconds

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="$SCRIPT_DIR/unit"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "Quick Check - Unit Tests"
echo "==========================================${NC}"
echo ""

# Track start time
START_TIME=$(date +%s)

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Run each unit test
for test_file in "$UNIT_DIR"/test-*.sh; do
    if [[ ! -f "$test_file" ]]; then
        continue
    fi
    
    TEST_NAME=$(basename "$test_file" .sh)
    ((TOTAL_TESTS++))
    
    echo -e "${YELLOW}Running: $TEST_NAME${NC}"
    
    # Run test and capture result
    if "$test_file" > "/tmp/${TEST_NAME}.log" 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}: $TEST_NAME"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗ FAILED${NC}: $TEST_NAME"
        echo "  See log: /tmp/${TEST_NAME}.log"
        ((FAILED_TESTS++))
    fi
    echo ""
done

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Print summary
echo ""
echo -e "${BLUE}=========================================="
echo "Quick Check Summary"
echo "==========================================${NC}"
echo "Total tests:   $TOTAL_TESTS"
echo -e "${GREEN}Passed:        $PASSED_TESTS${NC}"
echo -e "${RED}Failed:        $FAILED_TESTS${NC}"
echo "Duration:      ${DURATION}s"
echo ""

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    echo ""
    echo "Review logs in /tmp/test-*.log for details"
    exit 1
fi
