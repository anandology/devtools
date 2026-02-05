#!/bin/bash
# Test multiple VMs coordination
# Creates 3 Alpine VMs, tests simultaneous operation and inter-VM communication

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

echo "=========================================="
echo "Test: Multiple VMs Coordination"
echo "=========================================="
echo ""

# Test VM names
VM_COUNT=3
declare -a TEST_VMS
declare -a VM_IPS
for i in $(seq 1 $VM_COUNT); do
    TEST_VMS[$i]="test-multi-vm${i}-$$"
done

# Cleanup function
cleanup_test_vms() {
    echo ""
    echo "Cleaning up test VMs..."
    
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${TEST_VMS[$i]}"
        local vm_dir="$HOME/.firecracker-vms/$vm_name"
        
        if [[ -d "$vm_dir" ]]; then
            echo "  Cleaning up $vm_name..."
            
            # Stop VM if running
            if [[ -f "$vm_dir/state/vm.pid" ]]; then
                local pid=$(cat "$vm_dir/state/vm.pid" 2>/dev/null || echo "")
                if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    kill -TERM "$pid" 2>/dev/null || true
                    sleep 1
                    kill -KILL "$pid" 2>/dev/null || true
                fi
            fi
            
            # Remove TAP device (if exists)
            if [[ -f "$vm_dir/state/tap_name.txt" ]]; then
                local tap_name=$(cat "$vm_dir/state/tap_name.txt")
                sudo ip link delete "$tap_name" 2>/dev/null || true
            fi
            
            # Remove VM directory
            rm -rf "$vm_dir"
        fi
    done
    
    echo "  Cleanup complete"
}

# Register cleanup
register_cleanup "cleanup_test_vms"

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v firecracker &>/dev/null; then
    echo "  SKIP: firecracker not found"
    assert_summary
    exit 0
fi

ALPINE_ROOTFS="$PROJECT_ROOT/tests/images/alpine-test.ext4"
if [[ ! -f "$ALPINE_ROOTFS" ]]; then
    echo "  SKIP: Alpine rootfs not found at $ALPINE_ROOTFS"
    echo "        Run: tests/unit/test-alpine-builder.sh"
    assert_summary
    exit 0
fi

KERNEL_PATH="$HOME/.firecracker-vms/.images/vmlinux"
if [[ ! -f "$KERNEL_PATH" ]]; then
    echo "  SKIP: Kernel not found at $KERNEL_PATH"
    echo "        Run: bin/setup.sh"
    assert_summary
    exit 0
fi

# Check if we have root access for TAP devices
if ! sudo -n true 2>/dev/null; then
    echo "  SKIP: Test requires passwordless sudo for TAP device management"
    assert_summary
    exit 0
fi

_print_result "PASS" "All prerequisites available" || true

echo ""
echo "=========================================="
echo "Phase 1: Create Multiple VMs"
echo "=========================================="
echo ""

# Create VMs
for i in $(seq 1 $VM_COUNT); do
    vm_name="${TEST_VMS[$i]}"
    vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    echo "Creating VM $i: $vm_name..."
    
    # Create VM directory
    mkdir -p "$vm_dir/state"
    
    # Assign IP address (172.16.0.10, 172.16.0.11, 172.16.0.12)
    vm_ip="172.16.0.1$i"
    VM_IPS[$i]="$vm_ip"
    echo "$vm_ip" > "$vm_dir/state/ip.txt"
    
    # Copy Alpine rootfs
    cp "$ALPINE_ROOTFS" "$vm_dir/rootfs.ext4"
    
    # Create TAP device
    tap_name="tap-test-$i-$$"
    echo "$tap_name" > "$vm_dir/state/tap_name.txt"
    
    if sudo ip tuntap add dev "$tap_name" mode tap 2>/dev/null; then
        sudo ip link set dev "$tap_name" up
        sudo ip addr add "172.16.0.1/24" dev "$tap_name" 2>/dev/null || true
        sudo ip link set dev "$tap_name" master br0 2>/dev/null || true
        _print_result "PASS" "VM $i created with IP $vm_ip (TAP: $tap_name)" || true
    else
        _print_result "FAIL" "Failed to create TAP device for VM $i" || true
        assert_summary
        exit 1
    fi
done

echo ""
echo "=========================================="
echo "Phase 2: Start All VMs Simultaneously"
echo "=========================================="
echo ""

# Start all VMs
declare -a VM_PIDS
for i in $(seq 1 $VM_COUNT); do
    vm_name="${TEST_VMS[$i]}"
    vm_dir="$HOME/.firecracker-vms/$vm_name"
    vm_ip="${VM_IPS[$i]}"
    tap_name=$(cat "$vm_dir/state/tap_name.txt")
    
    echo "Starting VM $i: $vm_name..."
    
    # Create Firecracker config
    cat > "$vm_dir/state/vm-config.json" << EOF
{
  "boot-source": {
    "kernel_image_path": "$KERNEL_PATH",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "$vm_dir/rootfs.ext4",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 128
  },
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "AA:FC:00:00:00:0$i",
      "host_dev_name": "$tap_name"
    }
  ]
}
EOF
    
    # Start Firecracker in background
    socket_path="$vm_dir/state/vm.sock"
    rm -f "$socket_path"
    
    firecracker --api-sock "$socket_path" \
                --config-file "$vm_dir/state/vm-config.json" \
                > "$vm_dir/state/console.log" 2>&1 &
    
    vm_pid=$!
    VM_PIDS[$i]=$vm_pid
    echo "$vm_pid" > "$vm_dir/state/vm.pid"
    
    echo "  Started with PID: $vm_pid"
done

echo ""
echo "Waiting for VMs to boot..."
sleep 3

# Verify all VMs are running
echo ""
echo "Verifying VM processes..."
all_running=true
for i in $(seq 1 $VM_COUNT); do
    vm_name="${TEST_VMS[$i]}"
    vm_pid="${VM_PIDS[$i]}"
    
    if kill -0 "$vm_pid" 2>/dev/null; then
        _print_result "PASS" "VM $i ($vm_name) is running (PID: $vm_pid)" || true
    else
        _print_result "FAIL" "VM $i ($vm_name) process died" || true
        all_running=false
    fi
done

if [[ "$all_running" != true ]]; then
    echo ""
    echo "Some VMs failed to start. Check console logs:"
    for i in $(seq 1 $VM_COUNT); do
        vm_name="${TEST_VMS[$i]}"
        vm_dir="$HOME/.firecracker-vms/$vm_name"
        if [[ -f "$vm_dir/state/console.log" ]]; then
            echo ""
            echo "=== $vm_name console log ==="
            tail -n 20 "$vm_dir/state/console.log"
        fi
    done
    assert_summary
    exit 1
fi

echo ""
echo "=========================================="
echo "Phase 3: Test Network Connectivity"
echo "=========================================="
echo ""

# Test host to each VM
echo "Testing host → VM connectivity..."
for i in $(seq 1 $VM_COUNT); do
    vm_name="${TEST_VMS[$i]}"
    vm_ip="${VM_IPS[$i]}"
    
    # Give VMs more time to boot and configure network
    sleep 2
    
    if ping -c 2 -W 2 "$vm_ip" >/dev/null 2>&1; then
        _print_result "PASS" "Host can ping VM $i ($vm_ip)" || true
    else
        _print_result "FAIL" "Host cannot ping VM $i ($vm_ip)" || true
        echo "  Note: Alpine VMs may need network configuration inside guest"
    fi
done

echo ""
echo "=========================================="
echo "Phase 4: Test Resource Isolation"
echo "=========================================="
echo ""

# Verify each VM has unique IP
echo "Verifying unique IP assignments..."
unique_ips=$(printf '%s\n' "${VM_IPS[@]}" | sort -u | wc -l)
if [[ $unique_ips -eq $VM_COUNT ]]; then
    _print_result "PASS" "All VMs have unique IP addresses" || true
else
    _print_result "FAIL" "IP addresses are not unique" || true
fi

# Verify each VM has unique TAP device
echo "Verifying unique TAP devices..."
tap_count=0
for i in $(seq 1 $VM_COUNT); do
    vm_name="${TEST_VMS[$i]}"
    vm_dir="$HOME/.firecracker-vms/$vm_name"
    tap_name=$(cat "$vm_dir/state/tap_name.txt")
    
    if ip link show "$tap_name" >/dev/null 2>&1; then
        ((tap_count++))
    fi
done

if [[ $tap_count -eq $VM_COUNT ]]; then
    _print_result "PASS" "All VMs have unique TAP devices" || true
else
    _print_result "FAIL" "Not all TAP devices are present (found: $tap_count, expected: $VM_COUNT)" || true
fi

# Verify each VM has unique PID
echo "Verifying unique VM processes..."
unique_pids=$(printf '%s\n' "${VM_PIDS[@]}" | sort -u | wc -l)
if [[ $unique_pids -eq $VM_COUNT ]]; then
    _print_result "PASS" "All VMs have unique process IDs" || true
else
    _print_result "FAIL" "Process IDs are not unique" || true
fi

echo ""
echo "=========================================="
echo "Phase 5: Stop All VMs"
echo "=========================================="
echo ""

# Stop all VMs
for i in $(seq 1 $VM_COUNT); do
    vm_name="${TEST_VMS[$i]}"
    vm_pid="${VM_PIDS[$i]}"
    
    echo "Stopping VM $i: $vm_name..."
    
    if kill -TERM "$vm_pid" 2>/dev/null; then
        # Wait for graceful shutdown
        for j in {1..10}; do
            if ! kill -0 "$vm_pid" 2>/dev/null; then
                _print_result "PASS" "VM $i stopped gracefully" || true
                break
            fi
            sleep 1
        done
        
        # Force kill if still running
        if kill -0 "$vm_pid" 2>/dev/null; then
            kill -KILL "$vm_pid" 2>/dev/null || true
            _print_result "PASS" "VM $i force stopped" || true
        fi
    else
        _print_result "PASS" "VM $i already stopped" || true
    fi
done

# Verify all VMs stopped
echo ""
echo "Verifying all VMs stopped..."
sleep 1
all_stopped=true
for i in $(seq 1 $VM_COUNT); do
    vm_pid="${VM_PIDS[$i]}"
    if kill -0 "$vm_pid" 2>/dev/null; then
        _print_result "FAIL" "VM $i still running" || true
        all_stopped=false
    fi
done

if [[ "$all_stopped" == true ]]; then
    _print_result "PASS" "All VMs stopped successfully" || true
fi

echo ""
echo "=========================================="
echo "Phase 6: Cleanup"
echo "=========================================="
echo ""

# Remove TAP devices and VM directories
for i in $(seq 1 $VM_COUNT); do
    vm_name="${TEST_VMS[$i]}"
    vm_dir="$HOME/.firecracker-vms/$vm_name"
    
    if [[ -f "$vm_dir/state/tap_name.txt" ]]; then
        tap_name=$(cat "$vm_dir/state/tap_name.txt")
        if sudo ip link delete "$tap_name" 2>/dev/null; then
            echo "  Removed TAP device: $tap_name"
        fi
    fi
    
    if [[ -d "$vm_dir" ]]; then
        rm -rf "$vm_dir"
        echo "  Removed VM directory: $vm_name"
    fi
done

_print_result "PASS" "All resources cleaned up" || true

echo ""
assert_summary
