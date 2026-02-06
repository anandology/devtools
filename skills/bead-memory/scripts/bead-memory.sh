#!/usr/bin/env bash
# bead-memory: create a note in beads
# Usage: bead-memory.sh <category> <title> [description]
#
# Category is freeform. Common ones: til, decision, howto, context, worklog
set -euo pipefail

category="${1:?Usage: bead-memory.sh <category> <title> [description]}"
title="${2:?Usage: bead-memory.sh <category> <title> [description]}"
desc="${3:-}"

# Category must be a simple lowercase label (letters, numbers, hyphens)
if ! echo "$category" | grep -qE '^[a-z0-9-]+$'; then
    echo "Error: category must be lowercase letters, numbers, or hyphens (got '$category')" >&2
    exit 1
fi

# Create the note as a closed task with note + category labels
create_args=(
    --type task
    --labels "note,$category"
    --priority 4
    "$title"
    --silent
)

if [ -n "$desc" ]; then
    create_args+=(-d "$desc")
fi

id=$(bd create "${create_args[@]}")
bd close "$id" --reason "note" -q

echo "Created note $id [$category]: $title"
