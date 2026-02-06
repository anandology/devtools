#!/usr/bin/env bash
# bead-recall: retrieve notes from beads
# Usage: bead-recall.sh [--tag <category>] [--search <query>] [--long] [--limit N]
set -euo pipefail

tag=""
search=""
long=false
limit=20

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            tag="$2"
            shift 2
            ;;
        --search)
            search="$2"
            shift 2
            ;;
        --long)
            long=true
            shift
            ;;
        --limit)
            limit="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: bead-recall.sh [--tag <category>] [--search <query>] [--long] [--limit N]"
            echo ""
            echo "Options:"
            echo "  --tag <category>   Filter by category: til, decision, process, worklog"
            echo "  --search <query>   Search notes by keyword"
            echo "  --long             Show full descriptions"
            echo "  --limit N          Max notes to return (default: 20)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -n "$search" ]; then
    # Search mode
    args=(
        "$search"
        --label note
        --status closed
        --limit "$limit"
        --sort created
        --reverse
    )
    if [ -n "$tag" ]; then
        args+=(--label "$tag")
    fi
    if [ "$long" = true ]; then
        args+=(--long)
    fi
    bd search "${args[@]}"
else
    # List mode
    args=(
        --all
        --label note
        --status closed
        --limit "$limit"
        --sort created
        --reverse
    )
    if [ -n "$tag" ]; then
        args+=(--label "$tag")
    fi
    if [ "$long" = true ]; then
        args+=(--long)
    fi

    # Exclude archived notes by filtering out lines containing [archived]
    bd list "${args[@]}" | grep -v '\[archived' || true
fi
