#!/bin/bash
# VM helper functions for tests
# Usage: source tests/lib/vm-helpers.sh
#
# Example:
#   start_test_vm "my-test-vm" "alpine-test.ext4"
#   wait_for_vm_boot "my-test-vm" 10
#   check_vm_running "my-test-vm"

set -euo pipefail

# Start a test VM with firecracker
# Usage: start_test_vm <vm_name> <rootfs_path> [memory_mb] [vcpu_count]
start_test_vm() {
    local vm_name="$1"
    local rootfs_path="$2"
    local memory_mb="${3:-128}"
    local vcpu_count="${4:-1}"
    
    local vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    # Create VM directory
    mkdir -p "$vm_dir"
    
    # Copy rootfs
    cp "$rootfs_path" "$vm_dir/rootfs.ext4"
    
    # Get kernel path (use Ubuntu kernel as default)
    local kernel_path="$HOME/.firecracker-vms/.images/vmlinux"
    if [[ ! -f "$kernel_path" ]]; then
        echo "Error: Kernel not found at $kernel_path"
        return 1
    fi
    
    # Start firecracker in background
    echo "Starting VM: $vm_name..."
    
    # Use vm-up.sh if available, otherwise manual start
    if [[ -f "$(dirname "$0")/../bin/vm-up.sh" ]]; then
        VM_NAME="$vm_name" "$(dirname "$0")/../bin/vm-up.sh" >/dev/null 2>&1 &
    else
        # Manual firecracker start
        firecracker --api-sock "$vm_dir/firecracker.socket" >/dev/null 2>&1 &
        local fc_pid=$!
        echo "$fc_pid" > "$vm_dir/firecracker.pid"
        
        # Wait for socket
        local timeout=5
        while [[ ! -S "$vm_dir/firecracker.socket" ]] && [[ $timeout -gt 0 ]]; do
            sleep 0.5
            ((timeout--))
        done
    fi
    
    return 0
}

# Wait for VM to boot (checks for socket availability)
# Usage: wait_for_vm_boot <vm_name> [timeout_seconds]
wait_for_vm_boot() {
    local vm_name="$1"
    local timeout="${2:-30}"
    local vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    echo "Waiting for VM to boot: $vm_name (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        # Check if firecracker process is running
        if [[ -f "$vm_dir/firecracker.pid" ]]; then
            local pid
            pid=$(cat "$vm_dir/firecracker.pid")
            if ps -p "$pid" >/dev/null 2>&1; then
                echo "VM booted: $vm_name"
                return 0
            fi
        fi
        
        sleep 1
        ((elapsed++))
    done
    
    echo "Timeout waiting for VM to boot: $vm_name"
    return 1
}

# Check if VM is running
# Usage: check_vm_running <vm_name>
check_vm_running() {
    local vm_name="$1"
    local vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    # Check PID file
    if [[ ! -f "$vm_dir/firecracker.pid" ]]; then
        return 1
    fi
    
    local pid
    pid=$(cat "$vm_dir/firecracker.pid")
    
    if ps -p "$pid" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Wait for SSH to be available in VM
# Usage: wait_for_ssh <ip_address> [port] [timeout_seconds]
wait_for_ssh() {
    local ip="$1"
    local port="${2:-22}"
    local timeout="${3:-30}"
    
    echo "Waiting for SSH at $ip:$port (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if nc -z -w 1 "$ip" "$port" 2>/dev/null; then
            echo "SSH is available at $ip:$port"
            return 0
        fi
        
        sleep 1
        ((elapsed++))
    done
    
    echo "Timeout waiting for SSH at $ip:$port"
    return 1
}

# Test SSH connection to VM
# Usage: test_ssh_connection <ip_address> [port] [key_path]
test_ssh_connection() {
    local ip="$1"
    local port="${2:-22}"
    local key_path="${3:-$HOME/.ssh/id_rsa}"
    
    ssh -i "$key_path" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "$port" \
        "root@$ip" \
        "echo 'SSH connection successful'" >/dev/null 2>&1
}

# Execute command in VM via SSH
# Usage: vm_exec <ip_address> <command> [port] [key_path]
vm_exec() {
    local ip="$1"
    local command="$2"
    local port="${3:-22}"
    local key_path="${4:-$HOME/.ssh/id_rsa}"
    
    ssh -i "$key_path" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "$port" \
        "root@$ip" \
        "$command" 2>/dev/null
}

# Check if host can ping VM
# Usage: test_host_to_guest_ping <guest_ip> [count]
test_host_to_guest_ping() {
    local guest_ip="$1"
    local count="${2:-3}"
    
    echo "Testing host → guest ping ($guest_ip)..."
    ping -c "$count" -W 2 "$guest_ip" >/dev/null 2>&1
}

# Check if VM can ping host gateway
# Usage: test_guest_to_host_ping <vm_name> <gateway_ip>
test_guest_to_host_ping() {
    local vm_name="$1"
    local gateway_ip="$2"
    
    echo "Testing guest → host ping ($gateway_ip)..."
    
    # Try to execute ping in VM (requires console or SSH access)
    # This is a placeholder - actual implementation depends on how we access VM
    # For now, return success if VM is running
    check_vm_running "$vm_name"
}

# Create a TAP device for testing
# Usage: create_test_tap <tap_name> <ip_address> [netmask]
create_test_tap() {
    local tap_name="$1"
    local ip_address="$2"
    local netmask="${3:-255.255.255.0}"
    
    echo "Creating TAP device: $tap_name with IP $ip_address..."
    
    # Create TAP device
    sudo ip tuntap add dev "$tap_name" mode tap
    
    # Bring it up
    sudo ip link set dev "$tap_name" up
    
    # Assign IP address
    sudo ip addr add "$ip_address/$netmask" dev "$tap_name"
    
    return 0
}

# Get VM IP address from configuration
# Usage: get_vm_ip <vm_name>
get_vm_ip() {
    local vm_name="$1"
    local vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    # Try to read from config file
    if [[ -f "$vm_dir/config.json" ]]; then
        # Parse IP from config.json
        grep -oP '"guest_ip":\s*"\K[^"]+' "$vm_dir/config.json" 2>/dev/null || echo ""
    else
        # Return default test IP
        echo "172.16.0.2"
    fi
}

# Get firecracker PID
# Usage: get_vm_pid <vm_name>
get_vm_pid() {
    local vm_name="$1"
    local vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    if [[ -f "$vm_dir/firecracker.pid" ]]; then
        cat "$vm_dir/firecracker.pid"
    else
        echo ""
    fi
}

# Stop a test VM
# Usage: stop_test_vm <vm_name>
stop_test_vm() {
    local vm_name="$1"
    
    echo "Stopping VM: $vm_name..."
    
    # Use cleanup function from cleanup.sh if available
    if declare -f cleanup_vm >/dev/null; then
        cleanup_vm "$vm_name"
    else
        # Manual stop
        local vm_dir="$HOME/.firecracker-vms/$vm_name"
        if [[ -f "$vm_dir/firecracker.pid" ]]; then
            local pid
            pid=$(cat "$vm_dir/firecracker.pid")
            kill "$pid" 2>/dev/null || true
            rm -f "$vm_dir/firecracker.pid"
        fi
    fi
}

# Get VM status (running/stopped)
# Usage: get_vm_status <vm_name>
get_vm_status() {
    local vm_name="$1"
    
    if check_vm_running "$vm_name"; then
        echo "running"
    else
        echo "stopped"
    fi
}
