#!/usr/bin/env bash
# ratify.sh — single-commit ratification of a parked binder decision (FSM-4 Option A).
#
# Writes the decision into the binder's ## Decision journal AND flips
# status: parked → queued in one git commit. Narrows the crash window
# between the two writes to a single reviewable commit (ADR-004 amd
# tkt-136 Option A — "single-commit, crash window narrowed, not eliminated").
#
# Usage:
#   ratify.sh --binder <path/to/README.md> --decision "<decision text>"
#   ratify.sh --binder .lattice/tickets/tkt-42-foo/README.md --decision "use retry-lib not backoff-lib (source: preference retry-at-most-once)"
#
# Exit: 0 = ratified (committed), 1 = error, 2 = usage
set -euo pipefail

BINDER=""
DECISION=""

usage() { cat <<'USAGE'
Usage: ratify.sh --binder <README.md> --decision "<text>"
  --binder   Path to the ticket binder README.md (required)
  --decision Decision text to append to ## Decision journal (required)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binder)   BINDER="$2"; shift 2 ;;
    --decision) DECISION="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Error: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$BINDER" ]] || { echo "Error: --binder required" >&2; usage; exit 2; }
[[ -n "$DECISION" ]] || { echo "Error: --decision required" >&2; usage; exit 2; }
[[ -f "$BINDER" ]] || { echo "Error: binder not found: $BINDER" >&2; exit 1; }

BINDER_DIR=$(dirname "$BINDER")
BINDER_NAME=$(basename "$BINDER_DIR")

# Verify the binder is currently parked (precondition)
CURRENT_STATUS=$(grep -E '^\| status \|' "$BINDER" | head -1 | sed 's/.*| *//;s/ *|.*//')
if [[ "$CURRENT_STATUS" != "parked" ]]; then
  echo "Error: binder status is '$CURRENT_STATUS', expected 'parked'. ratify.sh only ratifies parked binders." >&2
  exit 1
fi

echo "ratify: $BINDER_NAME — status: parked → queued"

# 1. Append decision to ## Decision journal (insert before the next ## section or EOF)
#    The journal section is between "## Decision journal" and the next "## " header.
JOURNAL_MARKER="## Decision journal"
if grep -q "^${JOURNAL_MARKER}" "$BINDER"; then
  # Find the line number of the journal header
  JOURNAL_LINE=$(grep -n "^${JOURNAL_MARKER}" "$BINDER" | head -1 | cut -d: -f1)
  # Find the next ## section after the journal
  NEXT_SECTION=$(tail -n +"$((JOURNAL_LINE + 1))" "$BINDER" | grep -n "^## " | head -1 | cut -d: -f1)
  if [[ -n "$NEXT_SECTION" ]]; then
    INSERT_LINE=$(( JOURNAL_LINE + NEXT_SECTION ))
    # Insert before the next section
    sed -i '' "${INSERT_LINE}i\\
- ${DECISION} (ratified $(date -u +%Y-%m-%dT%H:%M:%SZ))
" "$BINDER"
  else
    # No next section — append to end of file
    echo "- ${DECISION} (ratified $(date -u +%Y-%m-%dT%H:%M:%SZ))" >> "$BINDER"
  fi
else
  echo "Error: binder has no ## Decision journal section" >&2
  exit 1
fi

# 2. Flip status: parked → queued in the field table
sed -i '' 's/^\(| status *| *\)parked/\1queued/' "$BINDER"

# 3. Single git commit (journal + status flip together)
cd "$BINDER_DIR/.."
# Resolve the repo root for git
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not in a git repo" >&2
  exit 1
fi
cd "$REPO_ROOT"

RELATIVE_BINDER=$(git ls-files --full-name "$BINDER" 2>/dev/null || echo "$BINDER")
git add "$RELATIVE_BINDER"
SUMMARY=$(echo "$DECISION" | head -c 72)
git commit -m "ratify(${BINDER_NAME}): ${SUMMARY}"

echo "ratify: done — single commit written (journal entry + parked → queued)"
