#!/usr/bin/env bash
# Batch-work merge gate helper for the finish-work skill (spc-186 A1, ADR-007).
#
# This is the scripted step that removes the .batch-work-active marker BEFORE
# merge, after a human ack — not "after" merge (the spc-186 A1 wording fix). The
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
#   LATTICE_BATCH_GATE_HOME  override the state home (tests / manual pin)
#   LATTICE_STATE_HOME       override the state home (marker-parent dir)
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

# Resolve the Lattice runtime state home (OUT OF REPO per ADR-011 / spc-282).
# The marker lives here, not at <MAIN>/.lattice/, so it never leaks as untracked
# dirt in a fresh customer repo. Priority:
#   1. LATTICE_BATCH_GATE_HOME / LATTICE_STATE_HOME — explicit override (tests)
#   2. _lattice-lib/scripts/lattice-state-home.sh — canonical resolver:
#        ${XDG_STATE_HOME:-$HOME/.local/state}/lattice/<sha1(common-dir)[:12]>
#   3. INLINE fallback — same algorithm, used if the helper cannot be found.
# Same algorithm as the hook lib (plugins/lattice/hooks/lib/batch-merge-gate.sh);
# duplicated here so the skill script does not depend on the plugin hook tree.
resolve_home() {
  local override="${LATTICE_BATCH_GATE_HOME:-${LATTICE_STATE_HOME:-}}"
  if [[ -n "$override" ]]; then
    printf '%s' "$override"
    return 0
  fi
  local helper
  helper="$(cd "${BASH_SOURCE[0]%/*}/../../_lattice-lib/scripts" 2>/dev/null && pwd)/lattice-state-home.sh"
  if [[ -f "$helper" ]]; then
    local resolved
    if resolved=$(bash "$helper" 2>/dev/null); then
      printf '%s' "$resolved"
      return 0
    fi
  fi
  # INLINE fallback (same algorithm as lattice-state-home.sh).
  local git_common fingerprint state_root
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    git_common=$(git rev-parse --git-common-dir 2>/dev/null || true)
    [[ -n "$git_common" && "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  [[ -n "$git_common" ]] || return 1
  fingerprint=$(printf '%s' "$git_common" | shasum 2>/dev/null | cut -c1-12 || true)
  [[ -n "$fingerprint" ]] || fingerprint=$(printf '%s' "$git_common" | sha1sum 2>/dev/null | cut -c1-12 || true)
  [[ -n "$fingerprint" ]] || return 1
  state_root="${XDG_STATE_HOME:-$HOME/.local/state}/lattice"
  local home="$state_root/$fingerprint"
  mkdir -p "$home" 2>/dev/null || true
  printf '%s' "$home"
  return 0
}

HOME_DIR=$(resolve_home 2>/dev/null || true)
if [[ -z "$HOME_DIR" ]]; then
  echo "Error: could not resolve Lattice state home; set LATTICE_BATCH_GATE_HOME or LATTICE_STATE_HOME" >&2
  if [[ "$ACTION" == "check" ]]; then
    # tkt-239: fail CLOSED on --check so a misresolvable home (submodule /
    # non-standard layout / no .lattice) does not silently bypass an active
    # .batch-work-active marker. The operator sets LATTICE_BATCH_GATE_HOME or
    # runs --remove --reason to escape (no silent allow).
    exit 1
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
    if ! command -v python3 >/dev/null 2>&1; then
      # Degrade: emit JSON without the interpreter (spc-212 A2 — no bare
      # "command not found"). Paths are Lattice-home paths (no quotes).
      printf '{"marker_present":%s,"escape_present":%s,"allowed":%s,"home":"%s","marker_path":"%s","python3":"missing"}\n' \
        "$marker_present" "$escape_present" "$allowed" "$HOME_DIR" "$MARKER_PATH"
      exit 0
    fi
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
    printf -- '- %s — batch-merge-gate escape authorized (spc-186 A1, ADR-007 §5b). rule_id=batch-merge-gate; reason="%s"; authorizer=operator; marker_removed=%s; ts=%s\n' \
      "$ts" "$REASON" "$MARKER_PATH" "$ts"
    # Clean a stale authorized-merge flag too so it does not accumulate.
    rm -f "$AUTH_PATH" 2>/dev/null || true
    exit 0
    ;;
esac
