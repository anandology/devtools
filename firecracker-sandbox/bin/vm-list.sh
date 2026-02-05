#!/bin/bash

# VM List Command - Show all VMs and their status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
    
    local hours=$((current_uptime / 3600))
    local minutes=$(((current_uptime % 3600) / 60))
    
    if [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Check if VMs directory exists
if [[ ! -d "$VMS_DIR" ]]; then
    echo "No VMs directory found at $VMS_DIR"
    echo "Initialize your first VM with: vm.sh init <name>"
    exit 0
fi

# Scan for VMs
VMS=()
for vm_dir in "$VMS_DIR"/*/ ; do
    if [[ -d "$vm_dir" ]] && [[ -d "$vm_dir/state" ]]; then
        VMS+=("$(basename "$vm_dir")")
    fi
done

# Check if any VMs exist
if [[ ${#VMS[@]} -eq 0 ]]; then
    echo "No VMs found."
    echo "Initialize your first VM with: vm.sh init <name>"
    exit 0
fi

# Sort VMs alphabetically
IFS=$'\n' VMS=($(sort <<<"${VMS[*]}"))
unset IFS

# Print header
printf "%-20s %-15s %-12s %-10s\n" "NAME" "IP" "STATUS" "UPTIME"
printf "%-20s %-15s %-12s %-10s\n" "----" "--" "------" "------"

# Process each VM
for vm_name in "${VMS[@]}"; do
    vm_dir="$VMS_DIR/$vm_name"
    state_dir="$vm_dir/state"
    
    # Read IP
    ip="-"
    if [[ -f "$state_dir/ip.txt" ]]; then
        ip=$(cat "$state_dir/ip.txt")
    fi
    
    # Determine status
    status="unknown"
    uptime="-"
    
    if [[ ! -f "$vm_dir/rootfs.ext4" ]]; then
        # VM is initialized but not built
        status="${YELLOW}pending${NC}"
    elif [[ -f "$state_dir/vm.pid" ]]; then
        # Check if process is alive
        pid=$(cat "$state_dir/vm.pid")
        if kill -0 "$pid" 2>/dev/null; then
            status="${GREEN}running${NC}"
            uptime=$(get_uptime "$pid")
        else
            status="${RED}crashed${NC}"
        fi
    else
        # VM is built but not running
        status="${CYAN}stopped${NC}"
    fi
    
    printf "%-20s %-15s %-22s %-10s\n" "$vm_name" "$ip" "$(echo -e "$status")" "$uptime"
done

echo ""
