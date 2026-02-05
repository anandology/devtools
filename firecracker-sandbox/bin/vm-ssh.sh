#!/bin/bash

# VM SSH Command - Connect to a running VM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Colors for output
RED='\033[0;31m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "VM name required. Usage: vm.sh ssh <name> [ssh-args]"
fi

VM_NAME="$1"
shift  # Remove VM name, keep remaining args for SSH

VM_DIR="$VMS_DIR/$VM_NAME"
STATE_DIR_VM="$VM_DIR/state"

# Validation
if [[ ! -d "$VM_DIR" ]]; then
    error "VM '$VM_NAME' does not exist"
fi

# Check if running
if [[ ! -f "$STATE_DIR_VM/vm.pid" ]]; then
    error "VM '$VM_NAME' is not running. Start it with: ~/vms/vm.sh up $VM_NAME"
fi

PID=$(cat "$STATE_DIR_VM/vm.pid")
if ! kill -0 "$PID" 2>/dev/null; then
    error "VM '$VM_NAME' is not running (stale PID). Start it with: ~/vms/vm.sh up $VM_NAME"
fi

# Load configuration
source "$VM_DIR/config.sh"
GUEST_IP=$(cat "$STATE_DIR_VM/ip.txt")

# Determine SSH key
SSH_KEY=""
if [[ -n "$SSH_KEY_PATH" ]] && [[ -f "$SSH_KEY_PATH" ]]; then
    SSH_KEY="-i ${SSH_KEY_PATH%.pub}"  # Remove .pub if present
    if [[ ! -f "$SSH_KEY" ]]; then
        SSH_KEY="-i $SSH_KEY_PATH"
    fi
fi

# Execute SSH connection
exec ssh -o StrictHostKeyChecking=no \
         -o UserKnownHostsFile=/dev/null \
         $SSH_KEY \
         "$USERNAME@$GUEST_IP" \
         "$@"
