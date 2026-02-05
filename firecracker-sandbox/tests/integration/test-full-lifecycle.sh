#!/bin/bash
# Test full VM lifecycle with Ubuntu
# Validates: init → build → up → ssh → down → destroy

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

echo "=========================================="
echo "Test: Full VM Lifecycle (Ubuntu)"
echo "=========================================="
echo ""

# Test VM name (unique per test run)
TEST_VM="test-lifecycle-$$"
VMS_DIR="$HOME/.firecracker-vms"
VM_DIR="$VMS_DIR/$TEST_VM"

# Set VMS_ROOT for the framework scripts
# This overrides the default location to use $HOME/.firecracker-vms
export VMS_ROOT="$HOME/.firecracker-vms"

# Cleanup function
cleanup_test_vm() {
    echo ""
    echo "Cleaning up test VM..."
    
    # Stop VM if running
    if [[ -f "$VM_DIR/state/vm.pid" ]]; then
        PID=$(cat "$VM_DIR/state/vm.pid" 2>/dev/null || echo "")
        if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
            echo "  Stopping VM..."
            "$BIN_DIR/vm-down.sh" "$TEST_VM" >/dev/null 2>&1 || true
            sleep 2
        fi
    fi
    
    # Destroy VM (requires sudo for TAP cleanup)
    if [[ -d "$VM_DIR" ]]; then
        echo "  Destroying VM..."
        sudo "$BIN_DIR/vm-destroy.sh" "$TEST_VM" --force >/dev/null 2>&1 || true
    fi
    
    echo "  Cleanup complete"
}

# Register cleanup
register_cleanup "cleanup_test_vm"

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v firecracker &>/dev/null; then
    echo "  SKIP: firecracker not found"
    assert_summary
    exit 0
fi

if ! command -v debootstrap &>/dev/null && ! command -v docker &>/dev/null; then
    echo "  SKIP: debootstrap or docker required for building Ubuntu VM"
    assert_summary
    exit 0
fi

if [[ ! -d "$HOME/.firecracker-vms/.images" ]] || [[ ! -f "$HOME/.firecracker-vms/.images/vmlinux" ]]; then
    echo "  SKIP: Kernel not found. Run setup.sh first"
    assert_summary
    exit 0
fi

# Check if we have root access for build/destroy
if ! sudo -n true 2>/dev/null; then
    echo "  SKIP: Test requires passwordless sudo for build/destroy operations"
    assert_summary
    exit 0
fi

_print_result "PASS" "All prerequisites available" || true

echo ""
echo "Setting up test environment..."

# Set up minimal bridge infrastructure for testing
# Create a fake bridge device for vm-init.sh validation
# STATE_DIR is defined in config.sh as $VMS_ROOT/state
STATE_DIR="$VMS_ROOT/state"
mkdir -p "$STATE_DIR"

# Create a real bridge for testing (or use existing one)
BRIDGE_NAME="br-firecracker-test"
if ! ip link show "$BRIDGE_NAME" &>/dev/null; then
    echo "  Creating test bridge: $BRIDGE_NAME"
    if sudo ip link add "$BRIDGE_NAME" type bridge 2>/dev/null; then
        sudo ip addr add 172.16.0.1/24 dev "$BRIDGE_NAME" 2>/dev/null || true
        sudo ip link set dev "$BRIDGE_NAME" up
        register_cleanup "sudo ip link delete '$BRIDGE_NAME' 2>/dev/null || true"
        
        # Create symlink for vm-init.sh check
        ln -sf "/sys/class/net/$BRIDGE_NAME" "$STATE_DIR/bridge"
        register_cleanup "rm -f '$STATE_DIR/bridge'"
        
        _print_result "PASS" "Test bridge created" || true
    else
        echo "  WARN: Could not create bridge, will use mock"
        # Create a mock bridge link for testing
        touch "$STATE_DIR/bridge-mock"
        ln -sf "$STATE_DIR/bridge-mock" "$STATE_DIR/bridge"
        register_cleanup "rm -f '$STATE_DIR/bridge' '$STATE_DIR/bridge-mock'"
        _print_result "PASS" "Mock bridge created" || true
    fi
else
    echo "  Using existing bridge: $BRIDGE_NAME"
    ln -sf "/sys/class/net/$BRIDGE_NAME" "$STATE_DIR/bridge"
    register_cleanup "rm -f '$STATE_DIR/bridge'"
    _print_result "PASS" "Using existing bridge" || true
fi

echo ""
echo "=========================================="
echo "Phase 1: VM Init"
echo "=========================================="
echo ""

# Run vm-init
echo "Running: vm-init.sh $TEST_VM"
INIT_OUTPUT=$("$BIN_DIR/vm-init.sh" "$TEST_VM" 2>&1) || INIT_FAILED=true

if [[ -z "${INIT_FAILED:-}" ]]; then
    _print_result "PASS" "VM init succeeded" || true
else
    _print_result "FAIL" "VM init failed" || true
    echo "  Error output:"
    echo "$INIT_OUTPUT" | head -10 | sed 's/^/    /'
    assert_summary
    exit 1
fi

# Verify VM directory created
if assert_dir_exists "$VM_DIR" "VM directory created"; then
    true
fi

# Verify config.sh created
if assert_file_exists "$VM_DIR/config.sh" "Config file created"; then
    true
fi

# Verify IP assigned
if assert_file_exists "$VM_DIR/state/ip.txt" "IP address assigned"; then
    ASSIGNED_IP=$(cat "$VM_DIR/state/ip.txt")
    echo "  Assigned IP: $ASSIGNED_IP"
fi

echo ""
echo "=========================================="
echo "Phase 2: VM Build"
echo "=========================================="
echo ""

# Reduce build size for faster testing
echo "Configuring minimal test VM..."
cat > "$VM_DIR/config.sh" << 'EOF'
# Minimal test VM configuration
CPUS=1
MEMORY=512
ROOTFS_SIZE="2G"
HOME_SIZE="1G"

USERNAME="test"
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"

UBUNTU_VERSION="22.04"
EOF

# Minimal package list for faster build
echo "openssh-server" > "$VM_DIR/apt-packages.txt"
echo "# Minimal test packages" >> "$VM_DIR/apt-packages.txt"

_print_result "PASS" "VM configured for minimal build" || true

# Run vm-build (this takes time)
echo ""
echo "Building Ubuntu VM (this may take 3-5 minutes)..."
echo "Note: This is the slowest part of the test"
echo ""

BUILD_START=$(date +%s)
if sudo "$BIN_DIR/vm-build.sh" "$TEST_VM" 2>&1 | while IFS= read -r line; do
    # Show progress indicators only
    if [[ "$line" =~ "Creating rootfs" ]] || \
       [[ "$line" =~ "Installing packages" ]] || \
       [[ "$line" =~ "Configuring" ]] || \
       [[ "$line" =~ "Creating TAP" ]] || \
       [[ "$line" =~ "ready" ]]; then
        echo "  $line"
    fi
done; then
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    _print_result "PASS" "VM build succeeded (${BUILD_TIME}s)" || true
else
    _print_result "FAIL" "VM build failed" || true
    assert_summary
    exit 1
fi

# Verify rootfs created
if assert_file_exists "$VM_DIR/rootfs.ext4" "Rootfs image created"; then
    true
fi

# Verify home volume created
if assert_file_exists "$VM_DIR/home.ext4" "Home volume created"; then
    true
fi

# Verify TAP device created
if [[ -f "$VM_DIR/state/tap_name.txt" ]]; then
    TAP_NAME=$(cat "$VM_DIR/state/tap_name.txt")
    if ip link show "$TAP_NAME" &>/dev/null; then
        _print_result "PASS" "TAP device created: $TAP_NAME" || true
    else
        _print_result "FAIL" "TAP device not found: $TAP_NAME" || true
    fi
fi

echo ""
echo "=========================================="
echo "Phase 3: VM Up"
echo "=========================================="
echo ""

# Run vm-up
echo "Starting VM..."
UP_START=$(date +%s)

if "$BIN_DIR/vm-up.sh" "$TEST_VM" 2>&1 | while IFS= read -r line; do
    # Show key progress messages
    if [[ "$line" =~ "Starting" ]] || \
       [[ "$line" =~ "Waiting" ]] || \
       [[ "$line" =~ "ready" ]] || \
       [[ "$line" =~ "SSH" ]]; then
        echo "  $line"
    fi
done; then
    UP_END=$(date +%s)
    UP_TIME=$((UP_END - UP_START))
    _print_result "PASS" "VM started successfully (${UP_TIME}s)" || true
else
    _print_result "FAIL" "VM start failed" || true
    assert_summary
    exit 1
fi

# Verify VM process running
if [[ -f "$VM_DIR/state/vm.pid" ]]; then
    VM_PID=$(cat "$VM_DIR/state/vm.pid")
    if kill -0 "$VM_PID" 2>/dev/null; then
        _print_result "PASS" "VM process running (PID: $VM_PID)" || true
    else
        _print_result "FAIL" "VM process not running" || true
    fi
fi

echo ""
echo "=========================================="
echo "Phase 4: SSH Access"
echo "=========================================="
echo ""

# Get VM IP
VM_IP=$(cat "$VM_DIR/state/ip.txt")
echo "Testing SSH to $VM_IP..."

# Load config to get username
source "$VM_DIR/config.sh"
SSH_USER="${USERNAME:-test}"

# Test SSH connection
if ssh -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o ConnectTimeout=5 \
       -o LogLevel=ERROR \
       "$SSH_USER@$VM_IP" \
       "echo 'SSH test successful'" >/dev/null 2>&1; then
    _print_result "PASS" "SSH connection successful" || true
else
    _print_result "FAIL" "SSH connection failed" || true
fi

# Test command execution
echo "Testing command execution via SSH..."
HOSTNAME_RESULT=$(ssh -o StrictHostKeyChecking=no \
                      -o UserKnownHostsFile=/dev/null \
                      -o LogLevel=ERROR \
                      "$SSH_USER@$VM_IP" \
                      "hostname" 2>/dev/null || echo "")

if [[ -n "$HOSTNAME_RESULT" ]]; then
    _print_result "PASS" "Command execution via SSH works (hostname: $HOSTNAME_RESULT)" || true
else
    _print_result "FAIL" "Command execution via SSH failed" || true
fi

# Test file operations
echo "Testing file operations via SSH..."
if ssh -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o LogLevel=ERROR \
       "$SSH_USER@$VM_IP" \
       "echo 'test content' > /tmp/test.txt && cat /tmp/test.txt" >/dev/null 2>&1; then
    _print_result "PASS" "File operations work" || true
else
    _print_result "FAIL" "File operations failed" || true
fi

echo ""
echo "=========================================="
echo "Phase 5: VM Down"
echo "=========================================="
echo ""

# Run vm-down
echo "Stopping VM..."
DOWN_START=$(date +%s)

if "$BIN_DIR/vm-down.sh" "$TEST_VM" >/dev/null 2>&1; then
    DOWN_END=$(date +%s)
    DOWN_TIME=$((DOWN_END - DOWN_START))
    _print_result "PASS" "VM stopped successfully (${DOWN_TIME}s)" || true
else
    _print_result "FAIL" "VM stop failed" || true
fi

# Verify VM process stopped
sleep 1
if [[ -f "$VM_DIR/state/vm.pid" ]]; then
    VM_PID=$(cat "$VM_DIR/state/vm.pid" 2>/dev/null || echo "")
    if [[ -n "$VM_PID" ]] && kill -0 "$VM_PID" 2>/dev/null; then
        _print_result "FAIL" "VM process still running" || true
    else
        _print_result "PASS" "VM process stopped" || true
    fi
else
    _print_result "PASS" "VM PID file removed" || true
fi

echo ""
echo "=========================================="
echo "Phase 6: VM Destroy"
echo "=========================================="
echo ""

# Run vm-destroy
echo "Destroying VM..."
if sudo "$BIN_DIR/vm-destroy.sh" "$TEST_VM" --force >/dev/null 2>&1; then
    _print_result "PASS" "VM destroyed successfully" || true
else
    _print_result "FAIL" "VM destroy failed" || true
fi

# Verify VM directory removed
if [[ ! -d "$VM_DIR" ]]; then
    _print_result "PASS" "VM directory removed" || true
else
    _print_result "FAIL" "VM directory still exists" || true
fi

# Verify TAP device removed
if [[ -n "${TAP_NAME:-}" ]]; then
    if ! ip link show "$TAP_NAME" &>/dev/null; then
        _print_result "PASS" "TAP device removed" || true
    else
        _print_result "FAIL" "TAP device still exists" || true
    fi
fi

echo ""
assert_summary
