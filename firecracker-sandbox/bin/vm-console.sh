#!/bin/bash
set -e

# VM Console Command - Start a VM with direct console access

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
    error "VM name required. Usage: vm.sh console <name>"
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
        error "VM '$VM_NAME' is already running (PID $pid). Stop it first with: vm.sh down $VM_NAME"
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
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw"
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

# Remove old socket if exists
rm -f "$FC_SOCKET"

FIRECRACKER_BIN="$BIN_DIR/firecracker"

info "========================================="
info "Starting VM '$VM_NAME' with console"
info "========================================="
info "VM: $VM_NAME"
info "IP: $GUEST_IP"
info "User: $USERNAME"
info ""
warn "Console controls:"
warn "  - Login as: $USERNAME (or root)"
warn "  - Exit VM: Ctrl-A then X (or 'sudo poweroff')"
warn "  - Ctrl-C will kill VM immediately"
info ""
info "Starting in 2 seconds..."
sleep 2

# Cleanup function
cleanup() {
    rm -f "$STATE_DIR_VM/vm.pid" "$FC_SOCKET"
}
trap cleanup EXIT

# Start Firecracker in foreground with console access
"$FIRECRACKER_BIN" --api-sock "$FC_SOCKET" --config-file "$FC_CONFIG"

# This line only executes after Firecracker exits
info ""
info "VM '$VM_NAME' stopped"
