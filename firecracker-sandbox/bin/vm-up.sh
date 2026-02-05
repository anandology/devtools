#!/bin/bash
set -e

# VM Up Command - Start a VM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "VM name required. Usage: vm.sh up <name>"
fi

VM_NAME="$1"
VM_DIR="$VMS_DIR/$VM_NAME"
STATE_DIR_VM="$VM_DIR/state"

# Validation
if [[ ! -d "$VM_DIR" ]]; then
    error "VM '$VM_NAME' does not exist. Run: vm.sh init $VM_NAME"
fi

if [[ ! -f "$VM_DIR/rootfs.ext4" ]]; then
    error "VM '$VM_NAME' is not built. Run: sudo vm.sh build $VM_NAME"
fi

# Check if already running
if [[ -f "$STATE_DIR_VM/vm.pid" ]]; then
    pid=$(cat "$STATE_DIR_VM/vm.pid")
    if kill -0 "$pid" 2>/dev/null; then
        error "VM '$VM_NAME' is already running (PID $pid)"
    else
        # Stale PID file
        rm -f "$STATE_DIR_VM/vm.pid" "$STATE_DIR_VM/vm.sock"
    fi
fi

# Load configuration
source "$VM_DIR/config.sh"

# Load state
GUEST_IP=$(cat "$STATE_DIR_VM/ip.txt")
TAP_NAME=$(cat "$STATE_DIR_VM/tap_name.txt")

# Check TAP device exists
if ! ip link show "$TAP_NAME" &>/dev/null; then
    error "TAP device $TAP_NAME not found. Rebuild VM with: sudo vm.sh build $VM_NAME"
fi

# Check for IP conflicts with other running VMs
for vm_dir in "$VMS_DIR"/*/ ; do
    if [[ -d "$vm_dir" ]] && [[ "$vm_dir" != "$VM_DIR/" ]]; then
        if [[ -f "$vm_dir/state/vm.pid" ]]; then
            other_pid=$(cat "$vm_dir/state/vm.pid")
            if kill -0 "$other_pid" 2>/dev/null; then
                other_ip=$(cat "$vm_dir/state/ip.txt" 2>/dev/null || echo "")
                if [[ "$other_ip" == "$GUEST_IP" ]]; then
                    error "IP $GUEST_IP already in use by $(basename "$vm_dir")"
                fi
            fi
        fi
    fi
done

info "Starting VM '$VM_NAME'..."

# Find kernel
KERNEL_PATH="$KERNELS_DIR/vmlinux-${KERNEL_VERSION}"
if [[ ! -f "$KERNEL_PATH" ]]; then
    error "Kernel not found at $KERNEL_PATH"
fi

# Create Firecracker configuration
FC_CONFIG="$STATE_DIR_VM/vm-config.json"
FC_SOCKET="$STATE_DIR_VM/vm.sock"

cat > "$FC_CONFIG" << EOF
{
  "boot-source": {
    "kernel_image_path": "$KERNEL_PATH",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off ip=$GUEST_IP::172.16.0.1:255.255.255.0::eth0:off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "$VM_DIR/rootfs.ext4",
      "is_root_device": true,
      "is_read_only": false
    },
    {
      "drive_id": "home",
      "path_on_host": "$VM_DIR/home.ext4",
      "is_root_device": false,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": $CPUS,
    "mem_size_mib": $MEMORY
  },
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "AA:FC:00:00:00:01",
      "host_dev_name": "$TAP_NAME"
    }
  ]
}
EOF

# Start Firecracker
info "Starting Firecracker..."
FIRECRACKER_BIN="$BIN_DIR/firecracker"

# Remove old socket if exists
rm -f "$FC_SOCKET"

# Start Firecracker in background
"$FIRECRACKER_BIN" --api-sock "$FC_SOCKET" --config-file "$FC_CONFIG" > "$STATE_DIR_VM/console.log" 2>&1 &
FC_PID=$!

# Save PID
echo "$FC_PID" > "$STATE_DIR_VM/vm.pid"

info "✓ Firecracker started (PID $FC_PID)"

# Wait for Firecracker to initialize
sleep 2

# Check if process is still alive
if ! kill -0 "$FC_PID" 2>/dev/null; then
    error "Firecracker process died. Check logs: $STATE_DIR_VM/console.log"
fi

# Wait for SSH to be ready
info "Waiting for VM to boot and SSH to be ready..."

SSH_READY=false
MAX_RETRIES=60
RETRY_COUNT=0
RETRY_DELAY=2

# Determine SSH key
SSH_KEY=""
if [[ -n "$SSH_KEY_PATH" ]] && [[ -f "$SSH_KEY_PATH" ]]; then
    SSH_KEY="-i ${SSH_KEY_PATH%.pub}"  # Remove .pub if present
    if [[ ! -f "$SSH_KEY" ]]; then
        SSH_KEY="-i $SSH_KEY_PATH"
    fi
fi

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if ssh -o ConnectTimeout=2 \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           $SSH_KEY \
           "$USERNAME@$GUEST_IP" \
           "exit 0" 2>/dev/null; then
        SSH_READY=true
        break
    fi
    
    # Check if VM process is still alive
    if ! kill -0 "$FC_PID" 2>/dev/null; then
        error "VM process died while waiting for SSH. Check logs: $STATE_DIR_VM/console.log"
    fi
    
    ((RETRY_COUNT++))
    sleep $RETRY_DELAY
done

if [[ "$SSH_READY" != true ]]; then
    # Kill VM process
    kill "$FC_PID" 2>/dev/null || true
    rm -f "$STATE_DIR_VM/vm.pid" "$FC_SOCKET"
    error "Timeout waiting for SSH. Check logs: $STATE_DIR_VM/console.log"
fi

info "✓ SSH is ready"

# Execute first-boot script if present
info "Checking for first-boot setup..."

if ssh -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o LogLevel=ERROR \
       $SSH_KEY \
       "$USERNAME@$GUEST_IP" \
       "sudo test -f /first-boot.sh" 2>/dev/null; then
    
    info "Running first-boot setup (this may take several minutes)..."
    
    # Execute first-boot script and show output
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o LogLevel=ERROR \
           $SSH_KEY \
           "$USERNAME@$GUEST_IP" \
           "sudo /first-boot.sh"; then
        
        # Delete first-boot script
        ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            $SSH_KEY \
            "$USERNAME@$GUEST_IP" \
            "sudo rm /first-boot.sh" 2>/dev/null || true
        
        info "✓ First-boot setup complete"
    else
        warn "First-boot setup had errors (VM is still running)"
    fi
else
    info "✓ No first-boot setup needed (fast boot)"
fi

# Mount home volume
info "Mounting home volume..."
ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    $SSH_KEY \
    "$USERNAME@$GUEST_IP" \
    "sudo mkdir -p /mnt/home && sudo mount /dev/vdb /mnt/home 2>/dev/null || true" 2>/dev/null || warn "Home volume mount may have failed"

info ""
info "========================================="
info "  VM '$VM_NAME' is ready"
info "========================================="
info "IP: $GUEST_IP"
info "SSH: ssh $USERNAME@$GUEST_IP"
info "Or: ~/vms/vm.sh ssh $VM_NAME"
info ""
info "Console log: $STATE_DIR_VM/console.log"
info ""
