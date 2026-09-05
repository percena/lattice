#!/usr/bin/env bash
# close-spec-primary.sh — gated Spec primary / epic close (tkt-473 A25).
#
# Before tkt-473 the Spec `status: done` flip + `gh issue close <primary>`
# were manual prose steps in finish-work (flow.md §3.6) with no chokepoint,
# no ledger, and no completion guard. `close-fixed-issues.sh` deliberately
# does NOT close the epic (progress ≠ Acceptance — blind auto-close is
# forbidden). This helper is the completion-causal close path finish-work
# invokes AFTER the last honest delivery has landed: it runs the guarded
# `spec-transition.py done` transition (A21/A22 guards: all children closed,
# exact child PR union, Acceptance complete, soak attested) and, ONLY on
# success, closes the GitHub Spec-primary issue. A failed transition refuses
# to close the epic (A25) — the operator resolves the guard or holds.
#
# The Spec `status:` flip + Spec ledger are written by spec-transition.py;
# this helper then stages the Spec file + its spc-N.jsonl ledger for a base
# commit (the finish-work flow commits + pushes once, the finish-commit.sh
# pattern). It does NOT commit/push itself.
#
# Usage:
#   close-spec-primary.sh --primary <issue-num> --soak-evidence-ref <ref> \
#       [--id <spc-N>] [--owner <owner>] [--attestation-ts <iso8601>] \
#       [--home <lattice home>] [--no-close-issue] [--dry-run]
#
#   --primary N          GitHub Spec-primary issue number (required)
#   --soak-evidence-ref  dogfood/soak evidence reference, e.g. pr-478 (required;
#                       A22 — the attestation must cite evidence)
#   --id N|spc-N         Spec id (default: derived from the primary issue's
#                       body `Contract lives in .lattice/specs/spc-N-…` line)
#   --owner owner        transition owner (default: claude)
#   --attestation-ts ts  ISO-8601 UTC ts (default: now — must post-date the
#                       last child merge; spec-transition.py validates this)
#   --home DIR           lattice home (default: <git toplevel>/.lattice)
#   --no-close-issue      flip the Spec + ledger but do not `gh issue close`
#                       (operator holds the epic open)
#   --dry-run            report the plan; mutate / close nothing
#
# Exit: 0 = Spec transitioned (and issue closed unless --no-close-issue);
#       1 = guarded transition REFUSED — epic NOT closed (A25); 2 = usage;
#       3 = io / gh error.
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/_lattice-lib/scripts"
bash "$LIB_DIR/ensure-python3.sh" || exit 1

PRIMARY=""
SOAK_REF=""
SPEC_ID=""
OWNER="claude"
ATTEST_TS=""
HOME_DIR=""
NO_CLOSE=false
DRY=false

usage() {
  cat >&2 <<'EOF'
Usage: close-spec-primary.sh --primary <issue-num> --soak-evidence-ref <ref> \
  [--id <spc-N>] [--owner <owner>] [--attestation-ts <iso8601>] \
  [--home <lattice home>] [--no-close-issue] [--dry-run]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --primary) PRIMARY="${2:-}"; shift 2 ;;
    --soak-evidence-ref) SOAK_REF="${2:-}"; shift 2 ;;
    --id) SPEC_ID="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --attestation-ts) ATTEST_TS="${2:-}"; shift 2 ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    --no-close-issue) NO_CLOSE=true; shift ;;
    --dry-run) DRY=true; shift ;;
    -h|--help) usage ;;
    *) echo "Error: unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$PRIMARY" ]] || { echo "Error: --primary required" >&2; usage; }
[[ -n "$SOAK_REF" ]] || { echo "Error: --soak-evidence-ref required (A22)" >&2; usage; }
[[ "$PRIMARY" =~ ^[1-9][0-9]*$ ]] || { echo "Error: --primary wants an issue number" >&2; usage; }

# --- Resolve lattice home + repo root ---------------------------------------
if [[ -z "$HOME_DIR" ]]; then
  if ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    HOME_DIR="$ROOT/.lattice"
  else
    HOME_DIR="$PWD/.lattice"
  fi
fi
REPO_ROOT="$(git -C "$HOME_DIR/.." rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

# --- Resolve the Spec id -----------------------------------------------------
if [[ -z "$SPEC_ID" ]]; then
  # Derive from the primary issue body: "Contract lives in .lattice/specs/spc-N-…"
  BODY=$(gh issue view "$PRIMARY" --json body --jq -r '.body' 2>/dev/null \
        || gh issue view "$PRIMARY" --json body 2>/dev/null \
        | python3 -c "import sys,json;print(json.load(sys.stdin)['body'])" 2>/dev/null || true)
  SPEC_ID=$(printf '%s\n' "$BODY" | grep -oE 'spc-[1-9][0-9]+' | head -1 || true)
  [[ -n "$SPEC_ID" ]] || { echo "Error: could not derive --id from issue #$PRIMARY body; pass --id <spc-N> explicitly" >&2; exit 2; }
fi
SPEC_ID="${SPEC_ID#spc-}"
SPEC_ID="spc-$SPEC_ID"

# --- Locate the spec file (find-spec.sh) -------------------------------------
SPEC_PATH=""
if [[ -f "$LIB_DIR/find-spec.sh" ]]; then
  SPEC_PATH=$("$LIB_DIR/find-spec.sh" --id "${SPEC_ID#spc-}" --home "$HOME_DIR" 2>/dev/null || true)
fi
[[ -n "$SPEC_PATH" && -f "$SPEC_PATH" ]] || { echo "Error: spec $SPEC_ID not found under $HOME_DIR/specs/" >&2; exit 3; }

# --- Attestation timestamp (default: now UTC) --------------------------------
if [[ -z "$ATTEST_TS" ]]; then
  ATTEST_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

ST="$LIB_DIR/spec-transition.py"
[[ -f "$ST" ]] || { echo "Error: spec-transition.py not found at $ST" >&2; exit 3; }

echo "close-spec-primary: transitioning $SPEC_ID (locked → done) before closing #$PRIMARY"
echo "  soak evidence ref: $SOAK_REF"
echo "  attestation ts:     $ATTEST_TS"

if [[ "$DRY" == "true" ]]; then
  echo "close-spec-primary: dry-run — running spec-transition.py done --dry-run"
  python3 "$ST" done "$SPEC_ID" "$OWNER" \
    --soak-evidence-ref "$SOAK_REF" --soak-attestation-ts "$ATTEST_TS" \
    --home "$HOME_DIR" --dry-run
  exit $?
fi

# --- A25: guarded transition; refuse to close the epic on failure ------------
if ! python3 "$ST" done "$SPEC_ID" "$OWNER" \
      --soak-evidence-ref "$SOAK_REF" --soak-attestation-ts "$ATTEST_TS" \
      --home "$HOME_DIR"; then
  rc=$?
  echo "close-spec-primary: REFUSED — spec-transition.py done exited $rc; epic #$PRIMARY NOT closed (A25)" >&2
  echo "  resolve the guard (open child / PR-set mismatch / open Acceptance / soak) or hold the epic open" >&2
  exit 1
fi

# --- Stage the Spec file + its ledger for the finish-work base commit -------
SPEC_REL="$(git -C "$REPO_ROOT" ls-files --full-name -- "$SPEC_PATH" 2>/dev/null || \
            python3 -c "import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))" "$SPEC_PATH" "$REPO_ROOT")"
LEDGER_REL=".lattice/.transition-ledger/${SPEC_ID}.jsonl"
git -C "$REPO_ROOT" add -- "$SPEC_REL" 2>/dev/null || true
git -C "$REPO_ROOT" add -- "$LEDGER_REL" 2>/dev/null || true
echo "close-spec-primary: staged $SPEC_REL + $LEDGER_REL for base commit"

if [[ "$NO_CLOSE" == "true" ]]; then
  echo "close-spec-primary: --no-close-issue — Spec flipped + ledger staged; epic #$PRIMARY left OPEN (operator hold)"
  exit 0
fi

# --- Close the GitHub Spec-primary issue -------------------------------------
if ! gh issue close "$PRIMARY" 2>/dev/null; then
  echo "close-spec-primary: WARNING — spec transitioned but gh issue close #$PRIMARY failed (network/perms?); Spec status is done, ledger staged" >&2
  exit 3
fi
echo "close-spec-primary: #$PRIMARY closed; $SPEC_ID status: done (guarded transition recorded)"
exit 0
