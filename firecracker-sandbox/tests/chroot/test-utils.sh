#!/bin/bash
# Test utils.sh functions. Expects bin/ and tests/ under the same project root
# (e.g. /tmp/bin and /tmp/tests when run in chroot).
#
# Run from project root or via run-chroot-tests.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root: tests/chroot -> tests -> project root
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"
UTILS_SH="$BIN_DIR/build/utils.sh"

assert_file_exists() {
    [[ -f "$1" ]] || { echo "FAIL: file not found: $1" >&2; return 1; }
}

assert_equals() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $msg"
        return 0
    fi
    echo "FAIL: $msg (expected '$expected', got '$actual')" >&2
    return 1
}

assert_file_contains() {
    local path="$1" needle="$2" msg="${3:-}"
    grep -qF "$needle" "$path" || { echo "FAIL: $msg ($path does not contain '$needle')" >&2; return 1; }
    echo "PASS: $msg"
    return 0
}

assert_file_exists "$UTILS_SH" || { echo "utils.sh not found at $UTILS_SH (BIN_DIR=$BIN_DIR)" >&2; exit 1; }
source "$UTILS_SH"

echo "=========================================="
echo "Testing utils.sh in chroot"
echo "=========================================="

# setup_hostname
setup_hostname "test-vm"
assert_equals "test-vm" "$(cat /etc/hostname)" "setup_hostname writes /etc/hostname"

# setup_etc_hosts
setup_etc_hosts "test-vm"
assert_file_contains /etc/hosts "127.0.0.1 localhost" "setup_etc_hosts has localhost"
assert_file_contains /etc/hosts "127.0.1.1 test-vm" "setup_etc_hosts has hostname"

# set_password (root must exist in chroot)
set_password "root" "testroot"
echo "PASS: set_password runs without error"

# add_fstab_line (if present) and setup_fstab
if type add_fstab_line &>/dev/null; then
    echo '# header' > /etc/fstab
    add_fstab_line "/dev/vda" "/" "ext4" "defaults" "0" "1"
    assert_file_contains /etc/fstab "/dev/vda" "add_fstab_line appends device"
fi

# setup_fstab
rm -f /etc/fstab
setup_fstab / /home /data
assert_file_contains /etc/fstab "/dev/vda" "setup_fstab has vda for root"
assert_file_contains /etc/fstab "/dev/vdb" "setup_fstab has vdb for /home"
assert_file_contains /etc/fstab "/dev/vdc" "setup_fstab has vdc for /data"
assert_equals "defaults,nofail" "$(awk '/\/home/{print $4}' /etc/fstab)" "setup_fstab uses nofail for non-root"

# setup_fstab first arg must be /
if setup_fstab /wrong 2>/dev/null; then
    echo "FAIL: setup_fstab should require first arg to be /" >&2
    exit 1
fi
echo "PASS: setup_fstab rejects first arg not /"

# setup_sshd
mkdir -p /etc/ssh
: > /etc/ssh/sshd_config
setup_sshd "yes" "yes" "yes"
assert_file_contains /etc/ssh/sshd_config "PermitRootLogin yes" "setup_sshd adds PermitRootLogin"
assert_file_contains /etc/ssh/sshd_config "PubkeyAuthentication yes" "setup_sshd adds PubkeyAuthentication"

# setup_ssh_keys (requires existing user)
if getent passwd root >/dev/null 2>&1; then
    KEY_FILE="/tmp/test-key.pub"
    echo "ssh-ed25519 AAAAB3NzaC1 test" > "$KEY_FILE"
    setup_ssh_keys "root" "$KEY_FILE"
    assert_file_exists /root/.ssh/authorized_keys "setup_ssh_keys creates authorized_keys"
    assert_file_contains /root/.ssh/authorized_keys "ssh-ed25519" "setup_ssh_keys appends key"
    rm -f "$KEY_FILE"
    echo "PASS: setup_ssh_keys for root"
fi

echo ""
echo "=========================================="
echo "All utils tests passed"
echo "=========================================="
