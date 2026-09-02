#!/usr/bin/env bash
# after-pr-open.sh — THE post-open step of create-pr (spc-337 A3 / ADR-012 §1).
#
# A successful `gh pr create` is the path point that stamps `→ pr-open`. This
# script chains the two calls the SKILL used to spell out in prose, in the only
# legal order:
#
#   1. verify-main-chain.sh --stage pr   — mutation-proof the PR (spc-254 A2/D5):
#      OPEN at the pushed HEAD OID, right repo, and (when supplied) the intended
#      base / head / body. A `FAILED:` proof exits non-zero HERE and the stamp
#      never runs (no binder / L0 write on a phantom PR).
#   2. stamp-pr-open.sh --pr N            — binder `prs` row + `status: pr-open`
#      + issue acceptance sync, one idempotent call (side-state guard unchanged).
#
# Usage:
#   after-pr-open.sh --pr <N> --expected-oid <HEAD> [--repo <owner/name>]
#                    [--expected-base <branch>] [--expected-head <branch>]
#                    [--expected-body-file <path>] [--binder <path>] [--check-all]
#
#   --repo defaults to origin (owner/name parsed from remote.origin.url).
#   --binder / --check-all pass through to stamp-pr-open.sh.
#
# _lattice-lib resolves through resolve-lattice-lib.sh (same trust anchor as
# SKILL.md Step 0; LATTICE_LIB_SCRIPTS is the explicit override).
#
# Exit: 0 = verified + stamped (or stamp skipped: no binder); 1 = proof FAILED
#       (recovery JSON on stderr from verify-main-chain) or stamp failure;
#       2 = usage.
set -euo pipefail

PR_N=""
EXPECTED_OID=""
REPO=""
EXPECTED_BASE=""
EXPECTED_HEAD=""
EXPECTED_BODY_FILE=""
BINDER=""
CHECK_ALL=false

usage() {
  cat >&2 <<'EOF'
Usage: after-pr-open.sh --pr <N> --expected-oid <HEAD> [--repo <owner/name>]
                        [--expected-base <branch>] [--expected-head <branch>]
                        [--expected-body-file <path>] [--binder <path>] [--check-all]

Runs verify-main-chain.sh --stage pr, then stamp-pr-open.sh --pr <N>.
A FAILED proof exits non-zero and the stamp does not run.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR_N="${2:-}"; shift 2 ;;
    --expected-oid) EXPECTED_OID="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --expected-base) EXPECTED_BASE="${2:-}"; shift 2 ;;
    --expected-head) EXPECTED_HEAD="${2:-}"; shift 2 ;;
    --expected-body-file) EXPECTED_BODY_FILE="${2:-}"; shift 2 ;;
    --binder) BINDER="${2:-}"; shift 2 ;;
    --check-all) CHECK_ALL=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$PR_N" ]] || { echo "Error: --pr is required" >&2; usage; }
[[ -n "$EXPECTED_OID" ]] || { echo "Error: --expected-oid is required (local HEAD captured before the push)" >&2; usage; }
if [[ ! "$PR_N" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --pr must be a positive GitHub PR number, got: $PR_N" >&2
  exit 2
fi

# --- Resolve _lattice-lib (trust anchor: the resolver's own install dir) ------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RESOLVE="$SCRIPT_DIR/../../_lattice-lib/scripts/resolve-lattice-lib.sh"
if [[ ! -f "$RESOLVE" ]]; then
  echo "Error: _lattice-lib is not installed beside create-pr ($RESOLVE missing)" >&2
  exit 1
fi
LIB=$(bash "$RESOLVE")
for helper in verify-main-chain.sh stamp-pr-open.sh; do
  if [[ ! -f "$LIB/$helper" ]]; then
    echo "Error: $helper missing from _lattice-lib at $LIB" >&2
    exit 1
  fi
done

# --- Repo identity: explicit --repo, else origin ------------------------------
if [[ -z "$REPO" ]]; then
  REPO=$(git config --get remote.origin.url 2>/dev/null \
    | sed -E 's|^.*github\.com[:/]||; s|\.git$||; s|/$||' || true)
fi
OWNER_REPO_RE='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
if [[ -z "$REPO" || ! "$REPO" =~ $OWNER_REPO_RE ]]; then
  echo "Error: could not resolve owner/name for the PR repo (pass --repo <owner/name>); got: '${REPO:-}'" >&2
  exit 2
fi

# --- 1. Mutation-proof the PR (halts the stamp on FAILED) ---------------------
VERIFY_ARGS=(--stage pr --pr "$PR_N" --expected-oid "$EXPECTED_OID" --repo "$REPO")
[[ -n "$EXPECTED_BASE" ]] && VERIFY_ARGS+=(--expected-base "$EXPECTED_BASE")
[[ -n "$EXPECTED_HEAD" ]] && VERIFY_ARGS+=(--expected-head "$EXPECTED_HEAD")
[[ -n "$EXPECTED_BODY_FILE" ]] && VERIFY_ARGS+=(--expected-body-file "$EXPECTED_BODY_FILE")
if ! bash "$LIB/verify-main-chain.sh" "${VERIFY_ARGS[@]}"; then
  echo "after-pr-open: PR proof FAILED for pr-$PR_N — stamp-pr-open NOT run; adjudicate via the recovery JSON above (re-verify before any binder/L0 write)" >&2
  exit 1
fi

# --- 2. Stamp the binder + issue (idempotent) ---------------------------------
STAMP_ARGS=(--pr "$PR_N" --repo "$REPO")
[[ -n "$BINDER" ]] && STAMP_ARGS+=(--binder "$BINDER")
[[ "$CHECK_ALL" == true ]] && STAMP_ARGS+=(--check-all)
if ! bash "$LIB/stamp-pr-open.sh" "${STAMP_ARGS[@]}"; then
  echo "after-pr-open: pr-$PR_N verified but stamp-pr-open FAILED — re-run: bash $(printf '%q' "$LIB/stamp-pr-open.sh") --pr $PR_N --repo $REPO" >&2
  exit 1
fi
echo "after-pr-open: pr-$PR_N verified + stamped (pr-open)"
