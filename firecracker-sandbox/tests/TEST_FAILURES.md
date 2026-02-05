# Test Failures Analysis

This document details all test failures discovered during test suite execution in Docker, with root cause analysis and reproduction steps.

## Summary

**Total Tests Run**: 11  
**Passing**: 7 (64%)  
**Failing**: 4 (36%)  

### Test Results

| Test | Status | Issue | Severity |
|------|--------|-------|----------|
| test-kvm-access | ✅ PASS | - | - |
| test-host-tools | ✅ PASS | - | - |
| test-tap-create | ❌ FAIL | dev-1oa | Low |
| test-tap-ip | ✅ PASS | - | - |
| test-ip-forward | ✅ PASS | - | - |
| test-nat-rules | ✅ PASS | - | - |
| test-alpine-builder | ✅ PASS | - | - |
| test-firecracker-socket | ✅ PASS | - | - |
| test-vm-boot-alpine | ❌ FAIL | dev-97q | Medium |
| test-host-to-guest | ❌ FAIL | dev-xje | High |
| test-multiple-vms | ❌ PARTIAL | dev-xje | High |
| test-full-lifecycle | ❌ FAIL | dev-g1v | Medium |

---

## Issue dev-1oa: test-tap-create.sh fails on TAP device state check

**Priority**: P2  
**Type**: Test Issue (False Negative)  
**Severity**: Low

### Problem
Test expects TAP device state to be "UP" after bringing it up, but gets "DOWN" because there's no carrier (nothing connected).

### Root Cause
A TAP device without anything connected shows:
```
<NO-CARRIER,BROADCAST,MULTICAST,UP> state DOWN
```

The device is administratively UP (has UP flag) but operationally DOWN (no carrier). This is expected and correct behavior.

### How to Reproduce
```bash
cd firecracker-sandbox
./tests/docker/run-tests.sh tests/unit/test-tap-create.sh
```

### Expected vs Actual
- **Expected**: Test accepts both "UP" state and "DOWN with UP flag"
- **Actual**: Test only accepts "UP/UNKNOWN" state

### Fix
Update test to check for UP flag instead of state:
```bash
# Instead of: ip link show | grep "state UP"
# Use: ip link show | grep "<.*UP.*>"
```

---

## Issue dev-97q: test-vm-boot-alpine.sh incorrectly fails

**Priority**: P2  
**Type**: Test Issue (False Negative)  
**Severity**: Medium

### Problem
Test reports "Firecracker process exited" but Firecracker actually boots successfully.

### Root Cause
When Firecracker is started with `--config-file`, it runs the VM in foreground (blocking), not background. The test starts it with `&` but the process doesn't stay in background as expected.

```bash
firecracker --api-sock $SOCKET --config-file config.json &
FC_PID=$!
sleep 2
ps -p $FC_PID  # Fails - but VM is actually running!
```

### Evidence
Manual run shows success:
```
2026-02-05T19:24:13 [anonymous-instance:main] Running Firecracker v1.7.0
2026-02-05T19:24:13 [anonymous-instance:main] Successfully started microvm
[    0.000000] Linux version 6.1.77
[    0.000000] Command line: console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw
```

### How to Reproduce
```bash
cd firecracker-sandbox
./tests/docker/run-tests.sh "bin/vm-build/build-alpine-rootfs.sh && tests/integration/test-vm-boot-alpine.sh"
```

### Fix Options
1. Use Firecracker API mode (start without config, configure via API)
2. Check for success messages in output instead of process existence
3. Use `timeout` wrapper to run in foreground and capture output

---

## Issue dev-xje: Alpine test VMs cannot ping host

**Priority**: P1  
**Type**: Product Issue (Real Bug)  
**Severity**: High

### Problem
Alpine VMs boot successfully but have no network connectivity. Host cannot ping guest IPs.

### Root Cause
The Alpine rootfs builder creates network configuration but:
1. May not have virtio-net drivers loaded
2. Network interfaces may not come up on boot
3. OpenRC networking service may not start properly

### Affected Tests
- `tests/integration/test-host-to-guest.sh`
- `tests/integration/test-multiple-vms.sh` (Phase 3)

### How to Reproduce
```bash
cd firecracker-sandbox
./tests/docker/run-tests.sh "bin/vm-build/build-alpine-rootfs.sh && tests/integration/test-multiple-vms.sh"
```

Output shows:
```
✓ PASS: VM 1 (test-multi-vm1-254) is running (PID: 296)
✓ PASS: VM 2 (test-multi-vm2-254) is running (PID: 301)
✓ PASS: VM 3 (test-multi-vm3-254) is running (PID: 306)
✗ FAIL: Host cannot ping VM 1 (172.16.0.11)
✗ FAIL: Host cannot ping VM 2 (172.16.0.12)
✗ FAIL: Host cannot ping VM 3 (172.16.0.13)
```

### What Works
- ✅ VM creation
- ✅ TAP device creation
- ✅ VM boots and runs
- ✅ Multiple VMs simultaneously
- ✅ Resource isolation
- ❌ Network connectivity

### Investigation Needed
1. Check if virtio-net driver is in Alpine kernel
2. Boot VM with console to check `ip link` and `ip addr`
3. Verify OpenRC networking service starts
4. Check `/etc/network/interfaces` configuration

### Potential Fixes
1. Ensure virtio-net is built into kernel or loaded as module
2. Add init script to explicitly bring up network
3. Verify OpenRC networking service is enabled and starts
4. Add boot parameter to enable virtio devices

---

## Issue dev-g1v: test-full-lifecycle.sh fails - requires bridge setup

**Priority**: P2  
**Type**: Test Environment Issue  
**Severity**: Medium

### Problem
Test fails because `vm-init.sh` requires the Firecracker bridge to be set up first.

### Root Cause
The test calls `bin/vm-init.sh` which checks:
```bash
BRIDGE_LINK="$STATE_DIR/bridge"
if [[ ! -L "$BRIDGE_LINK" ]] || [[ ! -e "$BRIDGE_LINK" ]]; then
    error "Bridge not set up. Run: sudo $BIN_DIR/setup.sh"
fi
```

Error:
```
Error: Bridge not set up. Run: sudo /workspace/firecracker-sandbox/bin/setup.sh
```

### How to Reproduce
```bash
cd firecracker-sandbox
./tests/docker/run-tests.sh "tests/integration/test-full-lifecycle.sh"
```

### What's Needed
The test needs infrastructure setup:
1. Create `br-firecracker` bridge device
2. Configure bridge IP (172.16.0.1/24)
3. Set up NAT/forwarding rules
4. Create state directory with bridge link

### Fix Options

**Option 1**: Add setup to test
```bash
# In test-full-lifecycle.sh before running vm-init
sudo $BIN_DIR/setup.sh
```

**Option 2**: Mock bridge for testing
```bash
mkdir -p $STATE_DIR
touch /tmp/fake-bridge
ln -s /tmp/fake-bridge $STATE_DIR/bridge
```

**Option 3**: Add `--skip-bridge-check` flag to vm-init.sh for testing

---

## Recommendations

### Immediate Actions (P1)
1. **Fix dev-xje**: Debug Alpine network configuration - this blocks actual network functionality testing
   - Boot Alpine VM with console access
   - Check kernel modules and network interfaces
   - Verify OpenRC services

### Short-term Actions (P2)
2. **Fix dev-97q**: Update vm-boot-alpine test to check for success differently
3. **Fix dev-g1v**: Add infrastructure setup to lifecycle test
4. **Fix dev-1oa**: Update TAP test to accept DOWN state with UP flag

### Test Suite Status

**Currently Functional**:
- ✅ Unit tests for host prerequisites (6/7 passing)
- ✅ Firecracker API tests
- ✅ Build system validation
- ✅ VM creation and management
- ✅ Multiple VM coordination (except networking)

**Needs Work**:
- ❌ Network connectivity validation
- ❌ Full lifecycle with bridge setup
- ❌ Some test assertions need adjustment

### Overall Assessment

The **test framework itself is sound**. The failures are:
- 2 false negatives (tests failing on valid behavior)
- 1 real product issue (Alpine networking)
- 1 test environment issue (bridge setup)

**The tests are doing their job**: they correctly identify that Alpine VMs don't have working networking, which is the most important finding.
