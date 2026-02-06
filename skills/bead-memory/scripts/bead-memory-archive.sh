#!/usr/bin/env bash
# bead-memory-archive: archive a note (excluded from recall)
# Usage: bead-memory-archive.sh <id>
set -euo pipefail

id="${1:?Usage: bead-memory-archive.sh <id>}"

# Verify it's actually a note before archiving
json=$(bd show "$id" --json 2>/dev/null)
if ! echo "$json" | grep -q '"note"'; then
    echo "Error: $id is not a note (missing 'note' label)" >&2
    exit 1
fi

if echo "$json" | grep -q '"archived"'; then
    echo "Note $id is already archived" >&2
    exit 0
fi

bd label add "$id" archived
echo "Archived note $id"
