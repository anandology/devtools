# Firecracker VM Framework - Testing Strategy

## Quick Start

Run all tests in Docker (recommended):
```bash
docker run --rm --privileged --device=/dev/kvm \
  -v $(pwd):/workspace \
  -w /workspace/firecracker-sandbox \
  ubuntu:22.04 \
  bash -c "
apt-get update -qq && apt-get install -y -qq curl tar e2fsprogs iproute2 iptables kmod openssh-client netcat-openbsd &&
curl -fsSL https://github.com/firecracker-microvm/firecracker/releases/download/v1.4.0/firecracker-v1.4.0-x86_64.tgz | tar -xz &&
mv release-v1.4.0-x86_64/firecracker-v1.4.0-x86_64 /usr/local/bin/firecracker &&
chmod +x /usr/local/bin/firecracker &&
tests/quick-check.sh
"
```

This runs all unit tests with proper privileges in an isolated environment. Result: **7/7 tests pass in <1 second**.

## Goals

1. **Fast feedback** - Tests should run in seconds, not minutes
2. **Modular testing** - Each component tested independently
3. **No sudo in CI** - Use Docker containers with `--privileged --device=/dev/kvm`
4. **Production confidence** - Fast tests with Alpine, integration tests with Ubuntu

## Test Rootfs Options

### Alpine Linux (Primary for Testing)
- **Size:** ~5-10MB vs 500MB+ for Ubuntu
- **Boot time:** ~500ms vs 2-5s
- **Use cases:** Network connectivity, SSH tests, basic VM lifecycle
- **Advantages:** Has package manager (apk), full shell, OpenSSH server

### Busybox Initramfs (Ultra-Fast)
- **Size:** ~2-3MB
- **Boot time:** <500ms
- **Use cases:** Boot tests, minimal network ping tests
- **Advantages:** Fastest possible, perfect for basic validation

### Ubuntu (Production)
- **Size:** ~500MB+
- **Boot time:** 2-5s
- **Use cases:** Production VMs, full integration tests
- **Advantages:** User's actual target OS

## Test Structure

```
tests/
├── images/
│   ├── alpine-test.ext4          # Alpine rootfs for fast tests
│   ├── busybox-test.cpio         # Busybox initramfs for ultra-fast tests
│   └── .gitignore                # Ignore test images
├── lib/
│   ├── assert.sh                 # Assertion functions
│   ├── cleanup.sh                # Cleanup utilities
│   └── vm-helpers.sh             # VM test utilities
├── unit/
│   ├── test-kvm-access.sh
│   ├── test-host-tools.sh
│   ├── test-tap-create.sh
│   ├── test-tap-ip.sh
│   ├── test-ip-forward.sh
│   └── test-nat-rules.sh
├── integration/
│   ├── test-full-lifecycle.sh    # Complete VM lifecycle
│   ├── test-network-stack.sh     # Network connectivity
│   ├── test-multiple-vms.sh      # Multiple VMs simultaneously
│   └── test-ubuntu-vm.sh         # Full Ubuntu VM test
├── docker/
│   ├── Dockerfile                # Test container
│   └── run-tests.sh              # Run tests in container
├── quick-check.sh                # Fast pre-commit checks
└── run-all-tests.sh              # Complete test suite
```

## Test Phases

### Phase 1: Host Prerequisites (No Sudo)

**test-kvm-access.sh**
- Checks `/dev/kvm` exists and is accessible
- Verifies KVM group membership
- Exit 0 = pass

**test-host-tools.sh**
- Verifies required tools: `ip`, `iptables`, `debootstrap`, `curl`, `firecracker`
- Checks versions if needed
- Exit 0 = pass

### Phase 2: Network Setup (Requires Sudo)

**test-tap-create.sh**
- Creates test TAP device
- Verifies it exists in `ip link show`
- Cleans up
- Tests both bridge and direct TAP modes

**test-tap-ip.sh**
- Creates TAP, assigns IP
- Pings self on TAP interface
- Verifies routing

**test-ip-forward.sh**
- Checks/enables IP forwarding
- Verifies sysctl setting

**test-nat-rules.sh**
- Adds test MASQUERADE rule
- Verifies iptables chain
- Tests FORWARD rules

### Phase 3: Build Components (Requires Sudo)

**Build Alpine Test Rootfs**
- Script: `bin/vm-build/build-alpine-rootfs.sh`
- Creates minimal Alpine with:
  - busybox utilities
  - OpenSSH server
  - Simple static network config
- Output: `tests/images/alpine-test.ext4` (~10MB)

**Build Busybox Initramfs**
- Script: `bin/vm-build/build-busybox-rootfs.sh`
- Creates minimal busybox with:
  - Basic networking (ip, ping, wget)
  - Simple init script
- Output: `tests/images/busybox-test.cpio` (~3MB)

**Build Ubuntu Rootfs** (for integration tests)
- Existing: `bin/vm-build.sh`
- Full debootstrap Ubuntu
- Used for integration tests only

### Phase 4: VM Runtime Tests (Mixed)

**test-firecracker-socket.sh** (No sudo)
- Starts firecracker with minimal config
- Verifies socket creation and API responses
- Tests clean shutdown

**test-vm-boot-minimal.sh** (No sudo)
- Boots VM with busybox initramfs
- No network, just boot test
- Verifies kernel boots and init runs
- ~1 second test

**test-vm-network-attach.sh** (No sudo)
- Boots Alpine VM with TAP attached
- Verifies firecracker accepts network config
- Doesn't test connectivity yet

**test-host-to-guest.sh** (Requires sudo for TAP setup)
- Boots Alpine VM with network
- Host pings guest IP
- Verifies ARP resolution

**test-guest-to-host.sh** (Requires sudo)
- Boots Alpine VM with console
- Automated login (SSH or console expect)
- Guest pings host TAP IP
- ~2 seconds boot + test

**test-guest-internet.sh** (Requires sudo)
- Same as above but pings `8.8.8.8`
- Tests NAT functionality

**test-ssh-access.sh** (Requires sudo)
- Boots Alpine VM with SSH
- Tests SSH connection and command execution
- Verifies SSH key authentication

### Phase 5: Integration Tests (Requires Sudo)

**test-full-lifecycle.sh**
- Uses Ubuntu VM
- Complete: init → build → up → ssh → down → destroy
- End-to-end validation

**test-multiple-vms.sh**
- Creates 3 Alpine VMs
- Starts simultaneously
- Tests inter-VM ping
- Verifies IP isolation

**test-ubuntu-vm.sh**
- Full Ubuntu VM build and boot
- Installs test packages
- Validates production workflow
- Slower but comprehensive

## Docker-based Testing

**Dockerfile**
```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    debootstrap curl iproute2 iptables \
    kmod sudo
# Install firecracker
# Copy framework
WORKDIR /workspace
CMD ["./tests/run-all-tests.sh"]
```

**Run in Docker**
```bash
docker build -t fc-test tests/docker/
docker run --privileged --device=/dev/kvm -v $(pwd):/workspace fc-test
```

## Test Execution

### Quick Check (Pre-Push)
```bash
./tests/quick-check.sh
```
- Runs Phase 1-2 only
- Takes ~10 seconds
- No VM builds

### Unit Tests
```bash
./tests/run-unit-tests.sh
```
- All unit tests with Alpine
- Takes ~30 seconds
- Fast feedback

### Full Suite
```bash
./tests/run-all-tests.sh
```
- All phases including Ubuntu integration
- Takes ~5 minutes
- Comprehensive validation

### CI/CD Pipeline
```bash
./tests/docker/run-tests.sh
```
- Runs in isolated container
- Full test suite
- No host contamination

## Test Output Format

Each test script outputs:
```
[PASS] Test name - description
[FAIL] Test name - error details
[SKIP] Test name - reason
```

Exit codes:
- 0 = all tests passed
- 1 = test failures
- 2 = setup/dependency issues

## Performance Targets

- Unit tests: <30s total
- Network tests with Alpine: <60s total
- Full integration with Ubuntu: <5m total
- Quick check: <15s

## Implementation Plan

See issue dev-[ID] for detailed implementation roadmap.
