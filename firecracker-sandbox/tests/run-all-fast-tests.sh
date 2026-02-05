#!/bin/bash
# Run all fast tests: unit + integration (Alpine)
# Target: <60 seconds total

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "Running All Fast Tests"
echo "Unit Tests + Integration Tests (Alpine)"
echo "==========================================${NC}"
echo ""

# Track start time
START_TIME=$(date +%s)

# Run unit tests first
echo -e "${BLUE}Phase 1: Unit Tests${NC}"
echo ""
if "$SCRIPT_DIR/quick-check.sh"; then
    UNIT_RESULT=0
else
    UNIT_RESULT=1
fi

echo ""
echo -e "${BLUE}Phase 2: Integration Tests${NC}"
echo ""
if "$SCRIPT_DIR/run-integration-tests.sh"; then
    INTEGRATION_RESULT=0
else
    INTEGRATION_RESULT=1
fi

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Print summary
echo ""
echo -e "${BLUE}=========================================="
echo "Complete Test Summary"
echo "==========================================${NC}"
echo "Duration:      ${DURATION}s"
echo ""

if [[ $UNIT_RESULT -eq 0 ]] && [[ $INTEGRATION_RESULT -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    if [[ $UNIT_RESULT -ne 0 ]]; then
        echo "  - Unit tests failed"
    fi
    if [[ $INTEGRATION_RESULT -ne 0 ]]; then
        echo "  - Integration tests failed"
    fi
    exit 1
fi
