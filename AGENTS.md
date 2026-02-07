# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**devtools** is a Firecracker VM management framework providing sudo-free daily VM operations. The main code lives in `firecracker-sandbox/`. It's entirely shell scripts (~3000 lines of bash).

## Key Commands

All commands run from `firecracker-sandbox/`:

```bash
# VM lifecycle
vm.sh init <name>              # Create VM config (no sudo)
sudo vm.sh build <name>        # Build VM images + TAP device
vm.sh up <name>                # Start VM (no sudo)
vm.sh console <name>           # Start with console access (no sudo)
vm.sh ssh <name> [args]        # SSH to VM (no sudo)
vm.sh down <name>              # Stop VM (no sudo)
vm.sh status <name>            # Check status (no sudo)
vm.sh list                     # List all VMs (no sudo)
sudo vm.sh destroy <name>      # Delete VM

# Global setup/cleanup (one-time, requires sudo)
sudo bin/setup.sh              # Create bridge network, download Firecracker
sudo bin/cleanup.sh            # Remove bridge and all VMs
```

### Testing

```bash
./tests/quick-check.sh              # Unit tests only (~15s)
./tests/run-all-fast-tests.sh       # Unit + Alpine tests (~60s)
./tests/run-all-tests.sh            # Full suite including Ubuntu (~5min)
./tests/run-all-tests.sh --fast     # Skip Ubuntu tests
./tests/run-all-tests.sh --unit-only

# Run individual tests directly:
./tests/unit/test-kvm-access.sh
./tests/integration/test-full-lifecycle.sh
```

## Architecture

### Sudo Separation (core design principle)

- **Privileged (one-time):** `setup.sh`, `vm build`, `vm destroy` — create bridge, TAP devices, rootfs images
- **Unprivileged (daily):** `vm up`, `vm down`, `vm ssh` — TAP devices are user-owned after build

### Script Organization

`vm.sh` is a CLI dispatcher that routes to `bin/vm-*.sh` scripts. All scripts source `bin/config.sh` for shared paths and constants.

```
firecracker-sandbox/
├── vm.sh                  # CLI dispatcher
├── bin/
│   ├── config.sh          # Global config (bridge IP, kernel version, paths)
│   ├── setup.sh / cleanup.sh
│   ├── vm-init.sh / vm-build.sh / vm-up.sh / vm-down.sh / vm-ssh.sh
│   ├── vm-console.sh / vm-status.sh / vm-list.sh / vm-destroy.sh
│   ├── first-boot.sh
│   └── build/             # Image building utilities
│       ├── make-image.sh / chroot-image.sh
│       ├── build-alpine-rootfs.sh / build-ubuntu-rootfs.sh
│       ├── configure-ubuntu-rootfs.sh
│       └── utils.sh       # Shared functions (setup_hostname, setup_ssh_keys, etc.)
├── tests/
│   ├── lib/               # assert.sh, cleanup.sh, vm-helpers.sh
│   ├── unit/              # Host prerequisite tests (no VMs)
│   ├── integration/       # Tests that boot VMs
│   └── chroot/            # In-chroot tests
├── vms/<name>/            # Per-VM instance dirs (config.sh, rootfs.ext4, home.ext4, state/)
└── kernels/               # Shared Firecracker kernels
```

### Networking

Single bridge `br-firecracker` at `172.16.0.1/24`. Each VM gets a dedicated TAP device and a unique IP in the `172.16.0.0/24` range. NAT provides internet access. VMs communicate directly via the bridge.

While this is the current design, using a seperate network for each VM without using a bridge is also being considered.

### Per-VM State

Each VM stores runtime state in `vms/<name>/state/`: `vm.pid`, `vm.sock`, `ip.txt`, `tap_name.txt`, `console.log`, `vm-config.json`.

### Shell Script Conventions

- `#!/bin/bash` with `set -e`
- `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` then source `config.sh`
- Color output: `error()` (red), `info()` (green), `warn()` (yellow)
- Validate inputs and prerequisites before costly operations
- `snake_case` for functions and variables

### Key Config Values (bin/config.sh)

- Firecracker: v1.7.0
- Kernel: 6.1.77
- Bridge: `br-firecracker` / `172.16.0.1/24`

---

# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

Each issue will clearly defined scope, notes for implementation and acceptance criteria.

## Memory (bead-memory)

This project uses the **bead-memory** skill for persistent knowledge across sessions. You MUST use it.

**At session start:** Run recall to load prior context:
```bash
skills/bead-memory/scripts/bead-recall.sh --limit 15
```

**When to create notes:** Use the bead-memory skill (see `.cursor/skills/bead-memory/SKILL.md`) to decide. In short: note surprising discoveries (til), decisions with reasoning (decision), procedures (howto), project context (context), and session summaries (worklog). Also create a note when the user says "remember this", "make a note", or similar.

**Creating a note:** Always use the script, never raw `bd`:
```bash
skills/bead-memory/scripts/bead-memory.sh <category> "<title>" "<description>"
```

**Recalling:** `skills/bead-memory/scripts/bead-recall.sh` with optional `--tag`, `--search`, `--long`.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Issue-First Development

**CRITICAL: Always create an issue BEFORE fixing a bug or implementing a feature.**

**Wrong workflow:**
1. ❌ Discover bug
2. ❌ Fix it immediately
3. ❌ Commit the fix
4. ❌ User asks "did you file an issue?"

**Correct workflow:**
1. ✅ Discover bug
2. ✅ Create issue: `bd create --type bug --priority PX --title "..." --description "..."`
3. ✅ Claim issue: `bd update <id> --status in_progress`
4. ✅ Fix the bug
5. ✅ Close issue: `bd close <id> --reason "Fixed in commit XXX"`
6. ✅ Commit with issue reference in message

**Why this matters:**
- Provides audit trail of what was broken and when
- Allows prioritization of fixes
- Documents the problem even if fix doesn't work
- Makes it easier to track regressions

## Testing and Quality Standards

**ALWAYS create a bug issue BEFORE fixing it.** Never commit a fix without tracking it in beads first.

### Test What You Actually Modified

**Golden Rule:** If you modify code for System X, you MUST test System X, not just System Y that uses similar code.

**Example:** If you modify `vm-build.sh` (Ubuntu VM builder):
- ❌ WRONG: Only test Alpine VMs because they're faster
- ✅ RIGHT: Test Ubuntu VMs or manually verify Ubuntu VM build works
- ✅ RIGHT: If you can't test Ubuntu, clearly state "UNTESTED on Ubuntu VMs"

**Before committing changes:**
1. Identify which systems your changes affect
2. Run tests for THOSE specific systems
3. If tests don't exist or are broken, do manual verification
4. If you can't test, document the risk clearly

### Be Honest About Test Failures

**NEVER say "tests are passing" or "only one test failing" unless you've actually verified it.**

**Required honesty:**
- ✅ "Fixed 3 tests: A, B, C. Did not test D, E, F."
- ✅ "Tests X, Y pass. Test Z still fails but unrelated to my changes."
- ✅ "No automated tests for this. Manually verified: [list what you did]"
- ❌ "Tests are passing" (when you only ran a subset)
- ❌ "Only one test failing" (when you didn't check all tests)

### Manual Verification for Critical Functionality

**For core user workflows, ALWAYS do manual end-to-end verification:**

**SSH Access (Critical):**
- If you modify VM build, user creation, or home directory setup
- You MUST manually SSH to a VM before committing
- Document: "Manually verified: Built VM, ran vm-up, SSH'd successfully"

**Network Connectivity (Critical):**
- If you modify network config, TAP devices, or routing
- You MUST verify ping/SSH connectivity
- Document: "Manually verified: Host→Guest ping works"

**VM Boot (Critical):**
- If you modify kernel, bootloader, or init
- You MUST verify VM boots to login prompt
- Document: "Manually verified: VM boots, console shows login"

### Test Failure Triage

**If a test fails:**
1. Determine: Is this a NEW failure from my changes, or pre-existing?
2. If NEW: Fix it before committing (don't break working tests)
3. If PRE-EXISTING: Document it clearly in commit message
4. If UNSURE: Be conservative - assume you broke it

### Create Issues for Gaps

**If you discover:**
- Missing test coverage → Create issue (type: bug or task, P1-P2)
- Broken test you can't fix → Create issue, add comment with investigation
- Manual-only verification → Create issue for automated test

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed):
   - Run tests that cover your changes (not just any tests)
   - Manual verification for critical functionality (SSH, networking, boot)
   - Document what you tested and results
   - Be honest about untested areas
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

