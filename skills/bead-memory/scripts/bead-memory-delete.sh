#!/usr/bin/env bash
# bead-memory-delete: permanently delete a note
# Usage: bead-memory-delete.sh <id>
set -euo pipefail

id="${1:?Usage: bead-memory-delete.sh <id>}"

# Verify it's actually a note before deleting
if ! bd show "$id" --json 2>/dev/null | grep -q '"note"'; then
    echo "Error: $id is not a note (missing 'note' label)" >&2
    exit 1
fi

bd delete "$id"
echo "Deleted note $id"
