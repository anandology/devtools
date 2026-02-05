#!/bin/bash
# First-boot automation script
# This script runs inside the VM on first boot to install packages

set -e

LOG_FILE="/var/log/first-boot.log"

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "First-boot setup started at $(date)"
echo "========================================="

# Get the username (the first non-root user)
USERNAME=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
if [[ -z "$USERNAME" ]]; then
    echo "Error: Could not determine username"
    exit 1
fi

echo "Running as root for user: $USERNAME"

# Package files location
APT_PACKAGES_FILE="/home/$USERNAME/apt-packages.txt"
NIX_PACKAGES_FILE="/home/$USERNAME/packages.nix"

# Install APT packages
if [[ -f "$APT_PACKAGES_FILE" ]]; then
    echo ""
    echo "========================================="
    echo "Installing APT packages..."
    echo "========================================="
    
    # Update package lists
    echo "Running apt-get update..."
    apt-get update -q
    
    # Read packages from file (skip comments and empty lines)
    PACKAGES=$(grep -v '^#' "$APT_PACKAGES_FILE" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
    
    if [[ -n "$PACKAGES" ]]; then
        echo "Packages to install: $PACKAGES"
        
        # Install packages one by one to continue on errors
        for package in $PACKAGES; do
            echo ""
            echo "Installing: $package"
            if apt-get install -y -q "$package"; then
                echo "  ✓ $package: OK"
            else
                echo "  ✗ $package: FAILED (continuing)"
            fi
        done
    else
        echo "No APT packages to install"
    fi
else
    echo "No apt-packages.txt file found, skipping APT packages"
fi

# Install Nix package manager
if [[ -f "$NIX_PACKAGES_FILE" ]]; then
    echo ""
    echo "========================================="
    echo "Installing Nix package manager..."
    echo "========================================="
    
    # Install Nix as the user (multi-user installation)
    if ! command -v nix &> /dev/null; then
        echo "Downloading and installing Nix..."
        su - "$USERNAME" -c 'curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes' || {
            echo "Nix installation failed, continuing..."
        }
        
        # Source Nix profile for this session
        if [[ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]]; then
            source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
        fi
    else
        echo "Nix already installed"
    fi
    
    # Install Nix packages
    NIX_PACKAGES=$(cat "$NIX_PACKAGES_FILE" | grep -v '^#' | grep -v '^[[:space:]]*$' | tr '\n' ' ')
    
    if [[ -n "$NIX_PACKAGES" ]] && command -v nix &> /dev/null; then
        echo ""
        echo "========================================="
        echo "Installing Nix packages..."
        echo "========================================="
        echo "Packages: $NIX_PACKAGES"
        
        for package in $NIX_PACKAGES; do
            echo ""
            echo "Installing: $package"
            if su - "$USERNAME" -c "nix-env -iA nixpkgs.$package"; then
                echo "  ✓ $package: OK"
            else
                echo "  ✗ $package: FAILED (continuing)"
            fi
        done
    else
        echo "No Nix packages to install or Nix not available"
    fi
else
    echo "No packages.nix file found, skipping Nix packages"
fi

echo ""
echo "========================================="
echo "First-boot setup complete at $(date)"
echo "========================================="
echo ""

exit 0
