#!/bin/bash

# VM Doctor - Diagnose VM environment health
# Run without sudo for basic checks; run with sudo for full iptables diagnostics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_CNT=0
WARN_CNT=0
FAIL_CNT=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_CNT++)) || true
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    [[ $# -gt 1 ]] && echo -e "       → Run: $2"
    ((WARN_CNT++)) || true
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    [[ $# -gt 1 ]] && echo -e "       → Run: $2"
    ((FAIL_CNT++)) || true
}

# Check if we have sudo for iptables
HAVE_SUDO=false
if [[ $EUID -eq 0 ]] || sudo -n iptables -L -n &>/dev/null; then
    HAVE_SUDO=true
fi

# Collect VM names (have state dir)
get_vm_names() {
    local names=()
    if [[ -d "$VMS_DIR" ]]; then
        for d in "$VMS_DIR"/*/; do
            [[ -d "$d" ]] && [[ -d "${d}state" ]] && names+=("$(basename "$d")")
        done
    fi
    echo "${names[@]:-}"
}

# Check if VM is built (has state/built)
is_vm_built() {
    local name="$1"
    [[ -f "$VMS_DIR/$name/state/built" ]]
}

# Get state dir for VM
vm_state_dir() {
    echo "$VMS_DIR/$1/state"
}

echo "Checking VM environment health..."
echo ""

# --- 1. Stale PID files (HIGH) ---
check_stale_pid_files() {
    local vms
    vms=($(get_vm_names))
    for name in "${vms[@]}"; do
        local pid_file="$VMS_DIR/$name/state/vm.pid"
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            if ! kill -0 "$pid" 2>/dev/null; then
                warn "VM '$name' has stale PID file (process $pid not running)" "vm.sh down $name"
            else
                pass "VM '$name' PID file valid (process $pid running)"
            fi
        fi
    done
}

# --- 2. Orphaned TAP devices (HIGH) ---
check_orphaned_tap_devices() {
    local vm_taps=()
    local vms
    vms=($(get_vm_names))
    for name in "${vms[@]}"; do
        local f="$VMS_DIR/$name/state/tap_name.txt"
        if [[ -f "$f" ]]; then
            vm_taps+=("$(cat "$f")")
        fi
    done
    local tap_count=0
    local orphan_count=0
    local tap
    while read -r tap; do
        [[ -z "$tap" ]] && continue
        ((tap_count++)) || true
        local found=false
        for t in "${vm_taps[@]}"; do
            [[ "$t" == "$tap" ]] && { found=true; break; }
        done
        if [[ "$found" == false ]]; then
            fail "TAP device '$tap' exists but no VM found with this TAP" "sudo ip link delete $tap"
            ((orphan_count++)) || true
        fi
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep '^tap-' || true)
    if [[ $tap_count -gt 0 ]] && [[ $orphan_count -eq 0 ]]; then
        pass "No orphaned TAP devices"
    fi
}

# --- 3. Missing TAP devices (HIGH) ---
check_missing_tap_devices() {
    local vms
    vms=($(get_vm_names))
    for name in "${vms[@]}"; do
        is_vm_built "$name" || continue
        local f="$VMS_DIR/$name/state/tap_name.txt"
        if [[ ! -f "$f" ]]; then
            fail "VM '$name' is built but missing state/tap_name.txt" "sudo vm.sh build $name"
            continue
        fi
        local tap_name
        tap_name=$(cat "$f")
        if ! ip link show "$tap_name" &>/dev/null; then
            fail "VM '$name' is built but TAP device '$tap_name' is missing" "sudo vm.sh build $name"
        else
            pass "VM '$name' TAP device '$tap_name' exists"
        fi
    done
}

# --- 4. Orphaned iptables FORWARD rules (MEDIUM) ---
check_orphaned_iptables_forward() {
    if ! $HAVE_SUDO; then return; fi
    # iptables -L FORWARD -n -v: in-iface is column 6, out-iface column 7
    local rules
    rules=$(sudo iptables -L FORWARD -n -v 2>/dev/null | awk '$6 ~ /^tap-/ {print $6, $7}' || true)
    while read -r tap out_iface; do
        [[ -z "$tap" ]] && continue
        local found=false
        for name in "$VMS_DIR"/*/; do
            [[ -d "$name" ]] || continue
            [[ -f "${name}state/tap_name.txt" ]] || continue
            if [[ "$(cat "${name}state/tap_name.txt")" == "$tap" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            fail "Orphaned iptables rule for $tap" "sudo iptables -D FORWARD -i $tap -o $out_iface -j ACCEPT"
        fi
    done <<< "$rules"
}

# --- 5. Missing iptables FORWARD rules (MEDIUM) ---
check_missing_iptables_forward() {
    if ! $HAVE_SUDO; then return; fi
    local vms
    vms=($(get_vm_names))
    for name in "${vms[@]}"; do
        is_vm_built "$name" || continue
        local state_dir="$VMS_DIR/$name/state"
        [[ -f "$state_dir/tap_name.txt" ]] && [[ -f "$state_dir/host_iface.txt" ]] || continue
        local tap_name host_iface
        tap_name=$(cat "$state_dir/tap_name.txt")
        host_iface=$(cat "$state_dir/host_iface.txt")
        ip link show "$tap_name" &>/dev/null || continue
        if ! sudo iptables -C FORWARD -i "$tap_name" -o "$host_iface" -j ACCEPT 2>/dev/null; then
            fail "VM '$name' has TAP device but missing iptables FORWARD rule" "sudo vm.sh build $name"
        else
            pass "VM '$name' FORWARD rule present"
        fi
    done
}

# --- 6. IP address conflicts (HIGH) ---
check_ip_conflicts() {
    declare -A ip_to_vms
    local vms
    vms=($(get_vm_names))
    for name in "${vms[@]}"; do
        local f="$VMS_DIR/$name/state/ip.txt"
        if [[ -f "$f" ]]; then
            local ip
            ip=$(cat "$f")
            if [[ -n "${ip_to_vms[$ip]:-}" ]]; then
                ip_to_vms["$ip"]="${ip_to_vms[$ip]} $name"
            else
                ip_to_vms["$ip"]="$name"
            fi
        fi
    done
    for ip in "${!ip_to_vms[@]}"; do
        local vms_list="${ip_to_vms[$ip]}"
        local count
        count=$(echo "$vms_list" | wc -w)
        if [[ "$count" -gt 1 ]]; then
            fail "VMs ($vms_list) share IP $ip" "Re-init one of the conflicting VMs"
        fi
    done
    if [[ ${#ip_to_vms[@]} -gt 0 ]]; then
        pass "No IP address conflicts"
    fi
}

# --- 7. Global NAT rules (MEDIUM) ---
check_global_nat_rules() {
    if ! $HAVE_SUDO; then return; fi
    local host_iface
    host_iface=$(detect_host_interface)
    if [[ -z "$host_iface" ]]; then
        warn "Could not detect host interface for NAT check"
        return
    fi
    local nat_ok=true
    if ! sudo iptables -t nat -C POSTROUTING -o "$host_iface" -j MASQUERADE 2>/dev/null; then
        fail "Global NAT MASQUERADE rule missing — VMs won't have internet" "sudo bin/setup.sh"
        nat_ok=false
    fi
    if ! sudo iptables -C FORWARD -i "$host_iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        fail "Global conntrack FORWARD rule missing — VMs won't have internet" "sudo bin/setup.sh"
        nat_ok=false
    fi
    if $nat_ok; then
        pass "Global NAT rules configured"
    fi
}

# --- 8. Missing kernel (LOW) ---
check_kernel() {
    local kernel_path="$KERNELS_DIR/vmlinux-${KERNEL_VERSION}"
    if [[ -f "$kernel_path" ]]; then
        pass "Kernel vmlinux-${KERNEL_VERSION} found"
    else
        fail "Kernel vmlinux-${KERNEL_VERSION} not found" "sudo bin/setup.sh"
    fi
}

# --- 9. State file consistency (MEDIUM) ---
check_state_consistency() {
    local vms
    vms=($(get_vm_names))
    for name in "${vms[@]}"; do
        is_vm_built "$name" || continue
        local state_dir="$VMS_DIR/$name/state"
        local missing=()
        for f in tap_name.txt host_iface.txt ip.txt gateway.txt; do
            [[ -f "$state_dir/$f" ]] || missing+=("$f")
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            fail "VM '$name' is built but missing state files: ${missing[*]}" "sudo vm.sh build $name"
            continue
        fi
        local tap_name gateway_file
        tap_name=$(cat "$state_dir/tap_name.txt")
        gateway_file=$(cat "$state_dir/gateway.txt")
        if ip link show "$tap_name" &>/dev/null; then
            local tap_ip
            tap_ip=$(ip -4 -o addr show "$tap_name" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1 || true)
            if [[ -n "$tap_ip" ]] && [[ "$tap_ip" != "$gateway_file" ]]; then
                fail "VM '$name' gateway.txt ($gateway_file) does not match TAP IP ($tap_ip)" "sudo vm.sh build $name"
            else
                pass "VM '$name' state files consistent"
            fi
        else
            pass "VM '$name' state files present (TAP not checked)"
        fi
    done
}

# --- 10. Orphaned Firecracker processes (MEDIUM) ---
check_orphaned_firecracker() {
    local pids=()
    while read -r pid; do
        [[ -n "$pid" ]] && pids+=("$pid")
    done < <(pgrep -x firecracker 2>/dev/null || true)
    for pid in "${pids[@]}"; do
        local found=false
        for name in "$VMS_DIR"/*/; do
            [[ -d "$name" ]] || continue
            local pf="${name}state/vm.pid"
            if [[ -f "$pf" ]] && [[ "$(cat "$pf")" == "$pid" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            fail "Firecracker process $pid running with no matching VM" "kill $pid (or find and vm.sh down <name>)"
        fi
    done
    if [[ ${#pids[@]} -eq 0 ]]; then
        pass "No orphaned Firecracker processes"
    fi
}

# --- 11. Disk image checks (LOW) ---
check_disk_images() {
    local vms
    vms=($(get_vm_names))
    for name in "${vms[@]}"; do
        is_vm_built "$name" || continue
        local vm_dir="$VMS_DIR/$name"
        if [[ ! -f "$vm_dir/rootfs.ext4" ]]; then
            fail "VM '$name' marked as built but missing rootfs.ext4" "sudo vm.sh build $name"
        fi
        if [[ ! -f "$vm_dir/home.ext4" ]]; then
            warn "VM '$name' is built but missing home.ext4" "Optional: rebuild or create home volume"
        fi
    done
}

# Run checks that don't require sudo first
check_stale_pid_files
check_orphaned_tap_devices
check_missing_tap_devices
check_ip_conflicts
check_kernel
check_state_consistency
check_orphaned_firecracker
check_disk_images

# Then iptables checks (only with sudo)
check_orphaned_iptables_forward
check_missing_iptables_forward
check_global_nat_rules

echo ""
if ! $HAVE_SUDO; then
    echo -e "${YELLOW}Run with sudo for full iptables diagnostics${NC}"
    echo ""
fi
echo "Summary: $PASS_CNT passed, $WARN_CNT warning(s), $FAIL_CNT problem(s) found"
