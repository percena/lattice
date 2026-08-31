#!/usr/bin/env bash
# state-dir-gc.sh — remove stale Lattice runtime-state entries from the state home.
#
# ADR-011 / spc-282 A6: a crashed batch leaves the relocated gate marker in
# $XDG_STATE_HOME/lattice/<repo-fingerprint>/ permanently opening the merge
# gate (fail-open). This GC removes stale entries by mtime so an orphaned
# batch does not leave a permanent fail-open. Called by start-work on entry.
#
# GC only REMOVES stale entries; it NEVER creates markers. Fail-closed-by-
# absence is unchanged (absent marker ⇒ merge allowed, same as today).
#
# Usage: state-dir-gc.sh [--stale-hours N] [--state-home <dir>]
# Env: LATTICE_STALE_MARKER_HOURS (default 24)
set -euo pipefail

STALE_HOURS="${LATTICE_STALE_MARKER_HOURS:-24}"
STATE_HOME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stale-hours) STALE_HOURS="${2:-}"; shift 2 ;;
    --state-home) STATE_HOME="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: state-dir-gc.sh [--stale-hours N] [--state-home <dir>]"; exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

# Resolve the state home via the canonical helper (same fingerprint as the
# merge gate, so GC targets the same dir the gate reads).
if [[ -z "$STATE_HOME" ]]; then
  SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
  HELPER="$SCRIPT_DIR/lattice-state-home.sh"
  if [[ -f "$HELPER" ]]; then
    STATE_HOME=$(bash "$HELPER" 2>/dev/null || true)
  fi
fi
[[ -n "$STATE_HOME" && -d "$STATE_HOME" ]] || { echo "state-dir-gc: no state home (nothing to GC)"; exit 0; }

STALE_MIN=$((STALE_HOURS * 60))
REMOVED=0

# Stale gate markers (.batch-work-active, .batch-merge-authorized) at the
# fingerprint root — these are the fail-open risk; a stale one opens the gate.
_gc_one() {
  local name="$1" path="$2"
  while IFS= read -r -d '' f; do
    rm -f "$f" && REMOVED=$((REMOVED+1))
  done < <(find "$path" -maxdepth 1 -name "$name" -mmin +"$STALE_MIN" -print0 2>/dev/null || true)
}

_gc_one '.batch-work-active' "$STATE_HOME"
_gc_one '.batch-merge-authorized' "$STATE_HOME"

# Stale coordinator spine json + transition-ledger .lock sidecars (older than
# threshold). These are not fail-open risks but are orphan-batch residue.
while IFS= read -r -d '' f; do
  rm -f "$f" && REMOVED=$((REMOVED+1))
done < <(find "$STATE_HOME/.coordinator" -name '*.json' -mmin +"$STALE_MIN" -print0 2>/dev/null || true)
while IFS= read -r -d '' f; do
  rm -f "$f" && REMOVED=$((REMOVED+1))
done < <(find "$STATE_HOME/.transition-ledger" -name '*.lock' -mmin +"$STALE_MIN" -print0 2>/dev/null || true)

echo "state-dir-gc: removed $REMOVED stale entr(y/ies) older than ${STALE_HOURS}h from $STATE_HOME"
