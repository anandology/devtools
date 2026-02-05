# Firecracker VM Test Framework

This directory contains a comprehensive test framework for the Firecracker VM management system.

## Structure

```
tests/
├── lib/                    # Shared test utilities
│   ├── assert.sh          # Assertion functions
│   ├── cleanup.sh         # Resource cleanup utilities
│   └── vm-helpers.sh      # VM lifecycle operations
├── unit/                   # Unit tests (no VM required)
│   ├── test-kvm-access.sh
│   ├── test-host-tools.sh
│   ├── test-tap-create.sh
│   ├── test-tap-ip.sh
│   ├── test-ip-forward.sh
│   └── test-nat-rules.sh
├── integration/            # Integration tests (VM boot required)
│   ├── test-firecracker-socket.sh
│   ├── test-vm-boot-alpine.sh
│   ├── test-host-to-guest.sh
│   ├── test-full-lifecycle.sh
│   └── test-multiple-vms.sh
├── images/                 # Test VM images (generated, not committed)
│   └── .gitignore
├── quick-check.sh         # Fast test runner (unit tests only)
├── run-all-fast-tests.sh  # Unit + fast integration tests
├── run-integration-tests.sh # Integration tests only
├── run-all-tests.sh       # Complete test suite
└── verify-test-lib.sh     # Test infrastructure verification
```

## Test Runners

### quick-check.sh
Runs all unit tests. Fast feedback loop for development.
- **Target**: Complete in <15 seconds
- **Tests**: Host prerequisites, no VM boot required
- **Usage**: `./tests/quick-check.sh`

### run-all-fast-tests.sh
Runs unit tests + fast integration tests with Alpine Linux.
- **Target**: Complete in <60 seconds
- **Tests**: Unit tests + Alpine VM boot tests
- **Usage**: `./tests/run-all-fast-tests.sh`

### run-all-tests.sh
Runs complete test suite including Ubuntu integration tests.
- **Target**: Complete in <5 minutes
- **Tests**: Unit + Fast integration + Production integration
- **Usage**: `./tests/run-all-tests.sh`
- **Options**:
  - `--fast` - Skip Ubuntu tests
  - `--unit-only` - Unit tests only
  - `--integration` - Integration tests only

## Test Library

### assert.sh
Assertion functions for test scripts:
- `assert_equals <expected> <actual> <message>`
- `assert_not_equals <not_expected> <actual> <message>`
- `assert_success <command> <message>`
- `assert_failure <command> <message>`
- `assert_file_exists <path> <message>`
- `assert_file_not_exists <path> <message>`
- `assert_dir_exists <path> <message>`
- `assert_contains <haystack> <needle> <message>`
- `assert_not_contains <haystack> <needle> <message>`
- `assert_summary` - Print test summary and exit with appropriate code

### cleanup.sh
Resource cleanup functions:
- `cleanup_vm <vm_name>` - Kill VM and clean up resources
- `cleanup_tap_device <tap_name>` - Remove TAP device
- `cleanup_mount <mount_point>` - Unmount filesystem
- `cleanup_directory <path>` - Remove directory
- `cleanup_file <path>` - Remove file
- `register_cleanup <function>` - Register cleanup function to run on exit

### vm-helpers.sh
VM lifecycle operations:
- `start_test_vm <vm_name> <rootfs_path> [memory_mb] [vcpu_count]`
- `wait_for_vm_boot <vm_name> [timeout_seconds]`
- `check_vm_running <vm_name>`
- `wait_for_ssh <ip_address> [port] [timeout_seconds]`
- `test_ssh_connection <ip_address> [port] [key_path]`
- `vm_exec <ip_address> <command> [port] [key_path]`
- `test_host_to_guest_ping <guest_ip> [count]`
- `create_test_tap <tap_name> <ip_address> [netmask]`
- `get_vm_ip <vm_name>`
- `stop_test_vm <vm_name>`

## Unit Tests

Unit tests verify host prerequisites without booting VMs:

1. **test-kvm-access.sh** - Verifies /dev/kvm access and kvm group membership
2. **test-host-tools.sh** - Checks all required tools are installed
3. **test-tap-create.sh** - Tests TAP device creation
4. **test-tap-ip.sh** - Tests TAP IP configuration and connectivity
5. **test-ip-forward.sh** - Verifies IP forwarding configuration
6. **test-nat-rules.sh** - Tests iptables NAT/MASQUERADE rules
7. **test-alpine-builder.sh** - Validates Alpine rootfs builder script

**Note**: Many unit tests require sudo access for network configuration. Some may show as "INFO" rather than "FAIL" when running without appropriate privileges.

## Integration Tests

Integration tests boot actual VMs and test full functionality:

### Fast Tests (Alpine Linux)
1. **test-firecracker-socket.sh** - Firecracker API and socket tests
2. **test-vm-boot-alpine.sh** - Basic Alpine VM boot test
3. **test-host-to-guest.sh** - Network connectivity from host to VM

### Production Tests (Ubuntu)
4. **test-full-lifecycle.sh** - Complete VM lifecycle: init → build → up → ssh → down → destroy
   - Creates a minimal Ubuntu VM
   - Tests all VM management commands
   - Validates SSH access and command execution
   - Takes 3-5 minutes (includes Ubuntu build)
   
5. **test-multiple-vms.sh** - Multiple VMs running simultaneously
   - Creates 3 Alpine VMs
   - Tests resource isolation (IPs, TAPs, PIDs)
   - Validates simultaneous operation
   - Tests cleanup and teardown

## Running Tests

### Quick Check (Recommended for Development)
```bash
./tests/quick-check.sh
```

### Run All Tests (Complete Suite)
```bash
./tests/run-all-tests.sh          # Full suite (~5 minutes)
./tests/run-all-tests.sh --fast   # Skip Ubuntu tests (<1 minute)
./tests/run-all-tests.sh --unit-only  # Unit tests only (<30s)
```

### Individual Tests
```bash
./tests/unit/test-kvm-access.sh
./tests/integration/test-full-lifecycle.sh
./tests/integration/test-multiple-vms.sh
```

### Verify Test Infrastructure
```bash
./tests/verify-test-lib.sh
```

## Test Images

Test images are generated by build scripts and stored in `tests/images/`:

- **alpine-test.ext4** - Alpine Linux test image (~10MB, boots in ~500ms)
- **busybox-test.cpio** - Busybox initramfs (~3MB, boots in <500ms) [coming soon]

Build Alpine test image:
```bash
sudo bin/vm-build/build-alpine-rootfs.sh
```

## Development Status

### Completed (✓)
- ✓ Test infrastructure (assert.sh, cleanup.sh, vm-helpers.sh)
- ✓ Alpine rootfs builder script
- ✓ Unit tests for host prerequisites
- ✓ Fast VM integration tests with Alpine
- ✓ Production integration tests with Ubuntu
- ✓ Multiple VMs coordination tests
- ✓ Full VM lifecycle tests
- ✓ quick-check.sh test runner
- ✓ run-all-tests.sh test runner

### In Progress (◐)
- ◐ Docker-based test environment

### Planned (○)
- ○ Busybox initramfs builder
- ○ CI/CD integration

## Contributing

When adding new tests:

1. Source the appropriate test libraries
2. Use assertion functions for checks
3. Register cleanup functions for resources
4. Add clear PASS/FAIL output
5. Update this README

Example test structure:
```bash
#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../lib/cleanup.sh"

# Your test code here
assert_equals "expected" "actual" "Test description"

assert_summary
```
