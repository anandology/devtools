#!/bin/bash
set -e

# Package distribution script - creates vms.zip for users

# Store the script directory first
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Creating vms.zip package..."

# Check that required files exist
if [[ ! -f "vm.sh" ]]; then
    echo "Error: vm.sh not found"
    exit 1
fi

if [[ ! -d "bin" ]]; then
    echo "Error: bin/ directory not found"
    exit 1
fi

# Create VERSION file
echo "1.0.0" > VERSION

# Create dist directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/../dist"

# Clean up any existing package
rm -f "$SCRIPT_DIR/../dist/vms.zip"

# Create a temporary directory for staging
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy files to vms/ subdirectory in temp location
mkdir -p "$TEMP_DIR/vms"
cp vm.sh "$TEMP_DIR/vms/"
cp -r bin "$TEMP_DIR/vms/"
cp VERSION "$TEMP_DIR/vms/"
cp README.md "$TEMP_DIR/vms/"

# Create the package from the temp directory
cd "$TEMP_DIR"
zip -r vms.zip vms/ \
    -x "*.swp" "*~" ".DS_Store" ".git/*" "__pycache__/*"

# Move the package to dist/
mv vms.zip "$SCRIPT_DIR/../dist/vms.zip"

# Return to original directory and clean up
cd "$SCRIPT_DIR"
rm -f VERSION

echo ""
echo "✓ Created dist/vms.zip"
echo ""
echo "Package contents:"
unzip -l ../dist/vms.zip | tail -n +4 | head -n -2
echo ""
echo "Installation instructions:"
echo "  1. Extract: unzip vms.zip (creates vms/ directory)"
echo "  2. Setup: cd vms && sudo bin/setup.sh"
echo "  3. Create VM: ~/vms/vm.sh init myvm"
echo ""
