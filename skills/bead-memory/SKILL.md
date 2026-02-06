---
name: bead-memory
description: >
  Record and recall project knowledge using bd (beads). Use proactively when
  you discover something surprising, make a design decision, figure out a
  non-obvious process, or finish a work session. Also use when the user says
  "remember this", "make a note", or "note that down".
---

# bead-memory: Project Memory

Persistent memory system for AI agents. Notes are stored as beads (bd issues)
and survive across sessions, agents, and tools.

## When to Create Notes (Proactively)

Create a note when you encounter knowledge that a future session would benefit
from. Use any category that fits - categories are freeform labels, not a fixed
enum. Choose short, descriptive, lowercase names.

**Common categories and when to use them:**

**til** - You discovered something non-obvious:
- A tool, API, or system behaved unexpectedly
- A gotcha or pitfall found during debugging
- A configuration requirement that wasn't documented
- Something the user explained that future sessions would benefit from

**decision** - A choice was made with reasoning:
- Why approach A was chosen over approach B
- Trade-offs that were weighed
- Constraints that drove the decision

**howto** - A multi-step procedure was figured out:
- Build, deploy, or test workflows discovered through trial and error
- Environment setup that required iteration
- Workarounds for known issues

**context** - Background knowledge about the project or user:
- Architecture and system constraints
- User preferences and conventions
- Environment requirements and assumptions

**worklog** - End of session summary:
- What was accomplished
- What was attempted but didn't work
- Open threads and next steps

These are suggestions, not a fixed list. If a project develops its own
categories (e.g. `api-contract`, `perf`, `compat`), use those. Check existing
notes (`scripts/bead-recall.sh`) to stay consistent with categories already
in use.

## When NOT to Create Notes

- Trivial facts easily found in docs or READMEs
- Things already captured in an existing note (run recall first)
- Temporary debugging state that won't matter tomorrow
- Information that's obvious to anyone familiar with the stack

## Project-Specific Judgment

Before deciding whether to create a note, check if the project's AGENTS.md
(or equivalent) has a **Memory Policy** section. If it does:

- Follow its "always note" directives even if the default criteria wouldn't trigger
- Respect its "never note" directives even if the default criteria would trigger
- Use any project-defined categories in addition to or instead of the common ones
- Project policy takes precedence over the default judgment above

## Creating Notes

Run: `scripts/bead-memory.sh <category> <title> [description]`

Category is any short lowercase label. Use existing categories for consistency,
or introduce new ones when the existing ones don't fit.

Examples:

```bash
scripts/bead-memory.sh til "ash lacks bash arrays" \
  "Alpine's default shell is ash, not bash. Arrays like arr=(a b) fail silently. Use space-delimited strings instead."

scripts/bead-memory.sh decision "Alpine over Ubuntu for base image" \
  "Chose Alpine: 5MB vs 200MB, faster boot, sufficient for our use case. Trade-off: musl libc means some glibc binaries won't run."

scripts/bead-memory.sh howto "Building Ubuntu rootfs" \
  "Requires debootstrap + chroot. Steps: 1) debootstrap focal, 2) mount proc/sys/dev, 3) chroot and configure systemd-networkd, 4) unmount."

scripts/bead-memory.sh context "Project assumes KVM access" \
  "All VM tests require /dev/kvm. CI runners must have nested virtualization enabled."

scripts/bead-memory.sh worklog "Refactored VM build scripts" \
  "Split monolithic build into stages. Added Ubuntu rootfs builder. Open: networking config still hardcoded."
```

Write concise titles that are scannable. Descriptions should be self-contained -
a future agent reading the note should understand it without extra context.

## Recalling Notes

Run: `scripts/bead-recall.sh [options]`

```bash
scripts/bead-recall.sh                        # recent notes (titles only)
scripts/bead-recall.sh --long                 # recent notes with descriptions
scripts/bead-recall.sh --tag til              # just TILs
scripts/bead-recall.sh --tag decision         # just decisions
scripts/bead-recall.sh --search "rootfs"      # keyword search across notes
```

**Do this at session start** to avoid re-learning things.
**Do this before debugging** to check if the issue was seen before.

## Archiving Notes

To archive a note that's no longer relevant but shouldn't be deleted:

```bash
scripts/bead-memory-archive.sh <id>
```

Archived notes are excluded from recall results.

## Deleting Notes

To permanently delete a note:

```bash
scripts/bead-memory-delete.sh <id>
```

## Important Rules

- **Always use these scripts for notes.** Never use `bd create`, `bd delete`,
  or other bd commands directly for memory operations.
- **Check before creating.** Run recall to avoid duplicating existing notes.
- **One insight per note.** Don't bundle unrelated things into a single note.
- **When the user says "remember this"** - determine the best category, summarize
  concisely, create the note, and confirm what was recorded.
