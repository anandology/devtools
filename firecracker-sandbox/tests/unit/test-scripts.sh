#!/bin/bash
# Test that all shell scripts are executable and have valid syntax

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../lib/assert.sh"

echo "=========================================="
echo "Testing Shell Scripts"
echo "=========================================="
echo ""

# List of scripts to test
SCRIPTS=(
    "bin/build/build-alpine-rootfs.sh"
    "bin/build/build-ubuntu-rootfs.sh"
    "bin/build/configure-ubuntu-rootfs.sh"
    "bin/vm-up.sh"
    "bin/vm-down.sh"
    "bin/vm-init.sh"
    "bin/vm-build.sh"
    "bin/vm-destroy.sh"
    "bin/vm-ssh.sh"
    "bin/vm-status.sh"
    "bin/vm-list.sh"
    "bin/vm-console.sh"
    "bin/vm-doctor.sh"
    "bin/setup.sh"
    "bin/cleanup.sh"
    "bin/first-boot.sh"
    "vm.sh"
)

for script in "${SCRIPTS[@]}"; do
    path="$PROJECT_ROOT/$script"
    echo "Checking $script..."
    assert_file_exists "$path" "$script exists"
    assert_executable "$path" "$script is executable"
    assert_valid_bash "$path" "$script has valid syntax"
    echo ""
done

assert_summary
