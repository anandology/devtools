#!/bin/bash
set -e

# VM Down Command - Stop a running VM

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
    error "VM name required. Usage: vm.sh down <name>"
fi

VM_NAME="$1"
VM_DIR="$VMS_DIR/$VM_NAME"
STATE_DIR_VM="$VM_DIR/state"

# Validation
if [[ ! -d "$VM_DIR" ]]; then
    error "VM '$VM_NAME' does not exist"
fi

# Check if running
if [[ ! -f "$STATE_DIR_VM/vm.pid" ]]; then
    info "VM '$VM_NAME' is not running"
    exit 0
fi

PID=$(cat "$STATE_DIR_VM/vm.pid")

# Check if process is actually alive
if ! kill -0 "$PID" 2>/dev/null; then
    info "VM '$VM_NAME' process is not running (stale PID file)"
    rm -f "$STATE_DIR_VM/vm.pid" "$STATE_DIR_VM/vm.sock"
    exit 0
fi

info "Stopping VM '$VM_NAME'..."

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

# Try graceful shutdown via SSH
info "Attempting graceful shutdown..."

if ssh -o ConnectTimeout=5 \
       -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o LogLevel=ERROR \
       $SSH_KEY \
       "$USERNAME@$GUEST_IP" \
       "sudo poweroff" 2>/dev/null; then
    
    info "Shutdown command sent, waiting for VM to stop..."
    
    # Wait for process to exit (up to 30 seconds)
    for i in {1..30}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            info "✓ VM stopped gracefully"
            rm -f "$STATE_DIR_VM/vm.pid" "$STATE_DIR_VM/vm.sock"
            exit 0
        fi
        sleep 1
    done
    
    warn "VM did not stop gracefully within 30 seconds"
fi

# Forceful shutdown
warn "Attempting forceful shutdown..."

# Send SIGTERM
if kill -0 "$PID" 2>/dev/null; then
    kill -TERM "$PID" 2>/dev/null || true
    
    # Wait 5 seconds
    for i in {1..5}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            info "✓ VM stopped (SIGTERM)"
            rm -f "$STATE_DIR_VM/vm.pid" "$STATE_DIR_VM/vm.sock"
            exit 0
        fi
        sleep 1
    done
fi

# Send SIGKILL as last resort
if kill -0 "$PID" 2>/dev/null; then
    warn "Force killing VM process..."
    kill -KILL "$PID" 2>/dev/null || true
    sleep 1
    
    if ! kill -0 "$PID" 2>/dev/null; then
        warn "✓ VM killed forcefully"
        rm -f "$STATE_DIR_VM/vm.pid" "$STATE_DIR_VM/vm.sock"
        exit 0
    else
        error "Failed to kill VM process"
    fi
fi

# Cleanup
rm -f "$STATE_DIR_VM/vm.pid" "$STATE_DIR_VM/vm.sock"
info "✓ VM '$VM_NAME' stopped"
