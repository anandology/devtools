#!/bin/bash

# VM Status Command - Show detailed VM information

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to get process uptime
get_uptime() {
    local pid=$1
    if [[ ! -f "/proc/$pid/stat" ]]; then
        echo "-"
        return
    fi
    
    local starttime=$(awk '{print $22}' /proc/$pid/stat)
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    local clock_ticks=$(getconf CLK_TCK)
    local process_start_sec=$((starttime / clock_ticks))
    local current_uptime=$((uptime_seconds - process_start_sec))
    
    local days=$((current_uptime / 86400))
    local hours=$(((current_uptime % 86400) / 3600))
    local minutes=$(((current_uptime % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Function to get memory usage
get_memory_usage() {
    local pid=$1
    if [[ ! -f "/proc/$pid/status" ]]; then
        echo "-"
        return
    fi
    
    local vm_rss=$(grep VmRSS /proc/$pid/status | awk '{print $2}')
    if [[ -n "$vm_rss" ]]; then
        local mb=$((vm_rss / 1024))
        echo "${mb} MB"
    else
        echo "-"
    fi
}

# Function to format file size
format_size() {
    local size_bytes=$1
    local size_gb=$(echo "scale=1; $size_bytes / 1024 / 1024 / 1024" | bc)
    echo "$size_gb GB"
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "VM name required. Usage: vm.sh status <name>"
fi

VM_NAME="$1"
VM_DIR="$VMS_DIR/$VM_NAME"
STATE_DIR_VM="$VM_DIR/state"

# Validation
if [[ ! -d "$VM_DIR" ]]; then
    error "VM '$VM_NAME' does not exist"
fi

# Determine status
STATUS="unknown"
STATUS_COLOR="$NC"
PID=""
UPTIME="-"
MEMORY_USAGE="-"

if [[ ! -f "$VM_DIR/rootfs.ext4" ]]; then
    STATUS="pending (not built)"
    STATUS_COLOR="$YELLOW"
elif [[ -f "$STATE_DIR_VM/vm.pid" ]]; then
    PID=$(cat "$STATE_DIR_VM/vm.pid")
    if kill -0 "$PID" 2>/dev/null; then
        STATUS="running"
        STATUS_COLOR="$GREEN"
        UPTIME=$(get_uptime "$PID")
        MEMORY_USAGE=$(get_memory_usage "$PID")
    else
        STATUS="crashed (stale pid)"
        STATUS_COLOR="$RED"
    fi
else
    STATUS="stopped"
    STATUS_COLOR="$CYAN"
fi

# Print status
echo "VM: $VM_NAME"
echo -e "Status: ${STATUS_COLOR}${STATUS}${NC}"

# Read configuration if available
if [[ -f "$VM_DIR/config.sh" ]]; then
    source "$VM_DIR/config.sh"
fi

# Read IP if available
IP="-"
if [[ -f "$STATE_DIR_VM/ip.txt" ]]; then
    IP=$(cat "$STATE_DIR_VM/ip.txt")
fi
echo "IP: $IP"

# Show username if available
if [[ -n "$USERNAME" ]]; then
    echo "Username: $USERNAME"
fi

# If pending, show next steps
if [[ "$STATUS" == "pending (not built)" ]]; then
    echo ""
    echo "Config: $VM_DIR/config.sh"
    echo "Next: sudo ~/vms/vm.sh build $VM_NAME"
    exit 0
fi

# Show uptime if running
if [[ "$STATUS" == "running" ]]; then
    echo "Uptime: $UPTIME"
fi

echo ""
echo "Resources:"
if [[ -n "$CPUS" ]]; then
    echo "  CPUs: $CPUS"
fi
if [[ -n "$MEMORY" ]]; then
    echo "  Memory: $MEMORY MB"
    if [[ "$STATUS" == "running" ]]; then
        echo "    Used: $MEMORY_USAGE"
    fi
fi

# Show TAP device
if [[ -f "$STATE_DIR_VM/tap_name.txt" ]]; then
    TAP_NAME=$(cat "$STATE_DIR_VM/tap_name.txt")
    echo "  TAP device: $TAP_NAME"
fi

echo ""
echo "Disks:"
if [[ -f "$VM_DIR/rootfs.ext4" ]]; then
    ROOTFS_SIZE=$(stat -f %z "$VM_DIR/rootfs.ext4" 2>/dev/null || stat -c %s "$VM_DIR/rootfs.ext4" 2>/dev/null || echo "0")
    echo "  Root: $(format_size $ROOTFS_SIZE) ($VM_DIR/rootfs.ext4)"
fi
if [[ -f "$VM_DIR/home.ext4" ]]; then
    HOME_SIZE=$(stat -f %z "$VM_DIR/home.ext4" 2>/dev/null || stat -c %s "$VM_DIR/home.ext4" 2>/dev/null || echo "0")
    echo "  Home: $(format_size $HOME_SIZE) ($VM_DIR/home.ext4)"
fi

if [[ "$STATUS" == "running" ]]; then
    echo ""
    echo "Process:"
    echo "  PID: $PID"
    echo ""
    echo "SSH: ssh $USERNAME@$IP"
    if [[ -f "$STATE_DIR_VM/console.log" ]]; then
        echo "Console log: $STATE_DIR_VM/console.log"
    fi
elif [[ "$STATUS" == "stopped" ]]; then
    echo ""
    echo "Start with: ~/vms/vm.sh up $VM_NAME"
elif [[ "$STATUS" == "crashed (stale pid)" ]]; then
    echo ""
    echo "VM crashed. Clean up with: ~/vms/vm.sh down $VM_NAME"
    echo "Then start again: ~/vms/vm.sh up $VM_NAME"
fi

echo ""
