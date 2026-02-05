#!/bin/bash
# Resource cleanup functions for tests
# Usage: source tests/lib/cleanup.sh
#
# Example:
#   cleanup_vm "test-vm"
#   cleanup_tap_device "tap-test"
#   cleanup_mount "/mnt/test"

set -euo pipefail

# Cleanup tracking
declare -a _CLEANUP_FUNCTIONS=()

# Register a cleanup function to be called on exit
# Usage: register_cleanup <function_name> [args...]
register_cleanup() {
    _CLEANUP_FUNCTIONS+=("$*")
}

# Execute all registered cleanup functions
# This is automatically called on script exit
_execute_cleanup() {
    local exit_code=$?
    
    if [[ ${#_CLEANUP_FUNCTIONS[@]} -gt 0 ]]; then
        echo "Running cleanup..."
        for cleanup_cmd in "${_CLEANUP_FUNCTIONS[@]}"; do
            eval "$cleanup_cmd" 2>/dev/null || true
        done
    fi
    
    exit $exit_code
}

# Set up cleanup trap
trap _execute_cleanup EXIT INT TERM

# Kill a process by PID
# Usage: cleanup_process <pid>
cleanup_process() {
    local pid="$1"
    
    if [[ -z "$pid" ]]; then
        return 0
    fi
    
    if ps -p "$pid" >/dev/null 2>&1; then
        echo "Killing process $pid..."
        kill "$pid" 2>/dev/null || true
        sleep 0.5
        
        # Force kill if still running
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
}

# Kill a VM by name (kills firecracker process)
# Usage: cleanup_vm <vm_name>
cleanup_vm() {
    local vm_name="$1"
    local vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    # Kill by PID file
    if [[ -f "$vm_dir/firecracker.pid" ]]; then
        local pid
        pid=$(cat "$vm_dir/firecracker.pid" 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            cleanup_process "$pid"
            rm -f "$vm_dir/firecracker.pid"
        fi
    fi
    
    # Kill by socket (find firecracker process using this socket)
    if [[ -S "$vm_dir/firecracker.socket" ]]; then
        local pids
        pids=$(lsof -t "$vm_dir/firecracker.socket" 2>/dev/null || true)
        for pid in $pids; do
            cleanup_process "$pid"
        done
        rm -f "$vm_dir/firecracker.socket"
    fi
    
    # Kill any remaining firecracker processes for this VM
    pkill -f "firecracker.*$vm_name" 2>/dev/null || true
    
    echo "Cleaned up VM: $vm_name"
}

# Remove a TAP device
# Usage: cleanup_tap_device <tap_name>
cleanup_tap_device() {
    local tap_name="$1"
    
    if ip link show "$tap_name" >/dev/null 2>&1; then
        echo "Removing TAP device: $tap_name..."
        sudo ip link delete "$tap_name" 2>/dev/null || true
    fi
}

# Unmount a filesystem
# Usage: cleanup_mount <mount_point>
cleanup_mount() {
    local mount_point="$1"
    
    if mount | grep -q "$mount_point"; then
        echo "Unmounting: $mount_point..."
        sudo umount "$mount_point" 2>/dev/null || true
    fi
}

# Remove a directory
# Usage: cleanup_directory <path>
cleanup_directory() {
    local path="$1"
    
    if [[ -d "$path" ]]; then
        echo "Removing directory: $path..."
        rm -rf "$path" 2>/dev/null || true
    fi
}

# Remove a file
# Usage: cleanup_file <path>
cleanup_file() {
    local path="$1"
    
    if [[ -f "$path" ]]; then
        echo "Removing file: $path..."
        rm -f "$path" 2>/dev/null || true
    fi
}

# Remove a socket file
# Usage: cleanup_socket <path>
cleanup_socket() {
    local path="$1"
    
    if [[ -S "$path" ]]; then
        echo "Removing socket: $path..."
        rm -f "$path" 2>/dev/null || true
    fi
}

# Clean up all test VMs (VMs with 'test-' prefix)
# Usage: cleanup_all_test_vms
cleanup_all_test_vms() {
    local vms_dir="$HOME/.firecracker-vms"
    
    if [[ ! -d "$vms_dir" ]]; then
        return 0
    fi
    
    for vm_dir in "$vms_dir"/test-*; do
        if [[ -d "$vm_dir" ]]; then
            local vm_name
            vm_name=$(basename "$vm_dir")
            cleanup_vm "$vm_name"
        fi
    done
}

# Clean up all test TAP devices (TAPs with 'tap-test-' prefix)
# Usage: cleanup_all_test_taps
cleanup_all_test_taps() {
    for tap in $(ip link show | grep -o 'tap-test-[^:]*' || true); do
        cleanup_tap_device "$tap"
    done
}

# Remove NAT iptables rule
# Usage: cleanup_nat_rule <interface>
cleanup_nat_rule() {
    local interface="${1:-eth0}"
    
    # Check if rule exists before removing
    if sudo iptables -t nat -C POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null; then
        echo "Removing NAT rule for $interface..."
        sudo iptables -t nat -D POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null || true
    fi
}

# Comprehensive cleanup for a test environment
# Usage: cleanup_test_environment <test_name>
cleanup_test_environment() {
    local test_name="${1:-test}"
    
    echo "Cleaning up test environment: $test_name..."
    
    # Clean up VM
    cleanup_vm "$test_name"
    
    # Clean up TAP device
    cleanup_tap_device "tap-$test_name"
    
    # Clean up any test directories
    cleanup_directory "/tmp/$test_name"
    
    echo "Test environment cleaned up: $test_name"
}
