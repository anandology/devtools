#!/bin/bash
set -e

# Package distribution script - creates vms.zip for users

cd "$(dirname "$0")"

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

# Clean up any existing package
rm -f vms.zip

# Create the package
zip -r vms.zip \
    vm.sh \
    bin/ \
    VERSION \
    README.md \
    -x "*.swp" "*~" ".DS_Store" ".git/*" "__pycache__/*" \
       "design.md" "package.sh" "*.zip"

# Remove VERSION file
rm -f VERSION

echo ""
echo "✓ Created vms.zip"
echo ""
echo "Package contents:"
unzip -l vms.zip | tail -n +4 | head -n -2
echo ""
echo "Installation instructions:"
echo "  1. Extract: unzip vms.zip -d ~/"
echo "  2. Setup: cd ~/vms && sudo bin/setup.sh"
echo "  3. Create VM: ~/vms/vm.sh init myvm"
echo ""
