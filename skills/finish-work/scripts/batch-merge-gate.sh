#!/usr/bin/env bash
# Batch-work merge gate helper for the finish-work skill (spc-187 A1, ADR-007).
#
# This is the scripted step that removes the .batch-work-active marker BEFORE
# merge, after a human ack — not "after" merge (the spc-187 A1 wording fix). The
# merge hook (plugins/lattice/hooks/lib/batch-merge-gate.sh) blocks `gh pr merge`
# while the marker is present; finish-work calls this helper to clear the gate
# once the operator has authorized the merge, then proceeds to merge.
#
# Human-adjudicated escape (ADR-007 §5b/§5c): the operator authorizes; this
# script executes the authorization and emits a structured trace line for the
# binder ## Decision journal. No agent self-adjudication.
#
# Usage:
#   batch-merge-gate.sh --check                     # exit 0=allowed, 1=blocked
#   batch-merge-gate.sh --status                    # print JSON status
#   batch-merge-gate.sh --remove --reason "user-authorized: <why>"
#                                                  # remove marker + emit trace
#
# Env:
#   LATTICE_BATCH_GATE_HOME  override the lattice home (tests / manual pin)
#
# Exit codes: 0 success/allowed, 1 blocked (marker present, no escape), 2 usage.

set -euo pipefail

BATCH_GATE_MARKER=".batch-work-active"
BATCH_GATE_AUTH=".batch-merge-authorized"

ACTION=""
REASON=""

usage() {
  cat >&2 <<'EOF'
Usage: batch-merge-gate.sh --check | --status | --remove --reason "<text>"
  --check    exit 0 if merge allowed (marker absent/escaped), 1 if blocked
  --status   print JSON: {marker_present, home, escape_present, allowed}
  --remove   remove the marker (human-authorized escape); --reason REQUIRED
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) ACTION="check"; shift ;;
    --status) ACTION="status"; shift ;;
    --remove) ACTION="remove"; shift ;;
    --reason) REASON="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ -n "$ACTION" ]] || usage
if [[ "$ACTION" == "remove" && -z "$REASON" ]]; then
  echo "Error: --remove requires --reason \"<structured text>\" (ADR-007 §5c)" >&2
  exit 2
fi

# Resolve the lattice home at the repo MAIN clone (not the worktree's .lattice).
# Same priority as the hook lib; duplicated here so the skill script does not
# depend on the plugin hook tree being installed.
resolve_home() {
  local git_common main_root
  if [[ -n "${LATTICE_BATCH_GATE_HOME:-}" ]]; then
    printf '%s' "$LATTICE_BATCH_GATE_HOME"
    return 0
  fi
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    git_common=$(git rev-parse --git-common-dir 2>/dev/null || true)
    [[ -n "$git_common" && "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  [[ -n "$git_common" ]] || return 1
  case "$git_common" in
    */.git) main_root="${git_common%/.git}" ;;
    */.git/*) main_root="${git_common%%/.git/*}" ;;
    *) main_root=$(git rev-parse --show-toplevel 2>/dev/null || true) ;;
  esac
  [[ -n "$main_root" && -d "$main_root/.lattice" ]] || return 1
  printf '%s/.lattice' "$main_root"
  return 0
}

HOME_DIR=$(resolve_home 2>/dev/null || true)
if [[ -z "$HOME_DIR" ]]; then
  echo "Error: could not resolve lattice home (MAIN .lattice/); set LATTICE_BATCH_GATE_HOME" >&2
  if [[ "$ACTION" == "check" ]]; then
    # Fail OPEN: an unresolved home cannot block a legitimate merge.
    exit 0
  fi
  exit 1
fi

MARKER_PATH="${HOME_DIR}/${BATCH_GATE_MARKER}"
AUTH_PATH="${HOME_DIR}/${BATCH_GATE_AUTH}"

marker_present=false
[[ -f "$MARKER_PATH" ]] && marker_present=true
escape_present=false
if [[ -f "$AUTH_PATH" ]]; then
  esc_reason=$(grep -v '^[[:space:]]*$' "$AUTH_PATH" 2>/dev/null | head -1 || true)
  [[ -n "$esc_reason" ]] && escape_present=true
fi
allowed=true
if $marker_present && ! $escape_present; then
  allowed=false
fi

case "$ACTION" in
  check)
    if $allowed; then exit 0; else exit 1; fi
    ;;
  status)
    BG_MARKER_PRESENT="$marker_present" \
    BG_ESCAPE_PRESENT="$escape_present" \
    BG_ALLOWED="$allowed" \
    BG_HOME="$HOME_DIR" \
    BG_MARKER_PATH="$MARKER_PATH" \
    python3 - <<'PY'
import json, os
print(json.dumps({
  "marker_present": os.environ.get("BG_MARKER_PRESENT") == "true",
  "escape_present": os.environ.get("BG_ESCAPE_PRESENT") == "true",
  "allowed": os.environ.get("BG_ALLOWED") == "true",
  "home": os.environ.get("BG_HOME") or "",
  "marker_path": os.environ.get("BG_MARKER_PATH") or "",
}))
PY
    ;;
  remove)
    if ! $marker_present; then
      echo "Note: marker already absent — nothing to remove: $MARKER_PATH" >&2
      exit 0
    fi
    # Human-authorized escape: remove the marker (the deliberate scripted step
    # BEFORE merge). The reason is part of the trace (ADR-007 §5c/§6).
    rm -f "$MARKER_PATH"
    # Emit a structured trace line for the binder ## Decision journal. finish-work
    # writes it into the binder; chat is not a trace.
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
    printf 'Decision journal entry (paste into binder ## Decision journal):\n'
    printf -- '- %s — batch-merge-gate escape authorized (spc-187 A1, ADR-007 §5b). rule_id=batch-merge-gate; reason="%s"; authorizer=operator; marker_removed=%s; ts=%s\n' \
      "$ts" "$REASON" "$MARKER_PATH" "$ts"
    # Clean a stale authorized-merge flag too so it does not accumulate.
    rm -f "$AUTH_PATH" 2>/dev/null || true
    exit 0
    ;;
esac
