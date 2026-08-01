#!/usr/bin/env bash
# Allocate Lattice artifact ids for specs or reviews.
#
# Usage: next-artifact-id.sh --kind spc|rev [--home <lattice-home>] [--claim]
#
# Team multi-clone identity:
#   spc  — NOT team SoT. Prefer GitHub issue number as spc-N (create issue first).
#          Local monotonic claim remains for tests / explicit offline degrade only.
#   rev  — R1 UTC timestamp token: YYYYMMDD-HHMMSSZ[+ -suffix]
#          Bare id is rev-<token>. stdout prints the token (no rev- prefix) so
#          callers keep writing: rev-${N}-<slug>.md
#
# --claim:
#   spc — atomic mkdir under claim-home/.ids/ (same-clone only; multi-clone unsafe)
#   rev — reserve path uniqueness under reviews/ + claim markers for the token
#
# Default --home (when omitted and LATTICE_HOME unset) is <show-toplevel>/.lattice
# Claim markers (spc) use lattice_claim_home (MAIN_ROOT/.lattice/.ids, gitignored).
#
# stdout:
#   spc → decimal id (1, 2, 10)
#   rev → R1 token (20260720-143052Z or 20260720-143052Z-a3f)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lattice-home.sh
source "$SCRIPT_DIR/_lattice-home.sh"

KIND=""
HOME_DIR=""
HOME_EXPLICIT=false
CLAIM=false

usage() {
  echo "Usage: next-artifact-id.sh --kind spc|rev [--home <path>] [--claim]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind) KIND="${2:-}"; shift 2 ;;
    --home) HOME_DIR="${2:-}"; HOME_EXPLICIT=true; shift 2 ;;
    --claim) CLAIM=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ "$KIND" != "spc" && "$KIND" != "rev" ]]; then
  usage
fi

lattice_export_roots
ROOT="${LATTICE_REPO_ROOT:-}"

if [[ -z "$HOME_DIR" ]]; then
  if ! HOME_DIR=$(lattice_default_home); then
    HOME_DIR=".lattice"
  fi
fi

# ---------------------------------------------------------------------------
# Review R1
# ---------------------------------------------------------------------------
if [[ "$KIND" == "rev" ]]; then
  REV_HOME="$HOME_DIR/reviews"
  DESIGN_HOME=""
  [[ -n "$ROOT" ]] && DESIGN_HOME="$ROOT/docs/design"
  MAIN_ROOT="${LATTICE_MAIN_ROOT:-}"
  MAIN_REV=""
  if [[ -n "$MAIN_ROOT" && "$HOME_DIR" != "$MAIN_ROOT/.lattice" ]]; then
    MAIN_REV="$MAIN_ROOT/.lattice/reviews"
  fi

  if $HOME_EXPLICIT; then
    CLAIM_DIR="$HOME_DIR/.ids"
  else
    CLAIM_HOME=$(lattice_claim_home 2>/dev/null || echo "$HOME_DIR")
    CLAIM_DIR="$CLAIM_HOME/.ids"
  fi

  # UTC timestamp to the second. `date -u +FMT` is POSIX, so there is no
  # BSD/GNU variant to fall back to — if it fails, the claim name would be
  # malformed, so stop instead of retrying the identical command.
  if ! TOKEN=$(date -u +%Y%m%d-%H%M%SZ 2>/dev/null) || [[ -z "$TOKEN" ]]; then
    echo "Error: date -u failed; cannot build a claim token" >&2
    exit 1
  fi

  rand_suffix() {
    # Always exactly three [a-z0-9] chars. Isolate the
    # urandom pipeline so pipefail/SIGPIPE cannot yield empty/short suffixes.
    local out=""
    set +e
    out=$(set +o pipefail 2>/dev/null; LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 3)
    set -e
    if [[ "${#out}" -ne 3 ]]; then
      out=$(printf '%03d' "$((RANDOM % 1000))")
    fi
    printf '%s' "$out"
  }

  token_taken() {
    local t="$1" base
    base="rev-${t}"
    [[ -e "$REV_HOME/${base}" || -e "$CLAIM_DIR/${base}" ]] && return 0
    # any file starting with rev-<token>
    if [[ -d "$REV_HOME" ]]; then
      local f
      for f in "$REV_HOME"/"${base}"*; do
        [[ -e "$f" ]] && return 0
      done
    fi
    if [[ -n "$DESIGN_HOME" && -d "$DESIGN_HOME" ]]; then
      local f
      for f in "$DESIGN_HOME"/"${base}"*; do
        [[ -e "$f" ]] && return 0
      done
    fi
    if [[ -n "$MAIN_REV" && -d "$MAIN_REV" ]]; then
      local f
      for f in "$MAIN_REV"/"${base}"*; do
        [[ -e "$f" ]] && return 0
      done
    fi
    return 1
  }

  CAND="$TOKEN"
  for _ in $(seq 1 32); do
    if ! token_taken "$CAND"; then
      if $CLAIM; then
        mkdir -p "$CLAIM_DIR" "$REV_HOME"
        if mkdir "$CLAIM_DIR/rev-${CAND}" 2>/dev/null; then
          printf '%s\n' "$CAND"
          exit 0
        fi
        # claim lost — try new suffix
        CAND="${TOKEN}-$(rand_suffix)"
        continue
      fi
      printf '%s\n' "$CAND"
      exit 0
    fi
    CAND="${TOKEN}-$(rand_suffix)"
  done
  echo "Error: could not allocate a unique rev R1 token after 32 attempts" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Spec — local monotonic (NOT team SoT)
# ---------------------------------------------------------------------------
echo "Warning: next-artifact-id --kind spc is NOT team SoT." >&2
echo "  Team path: gh issue create → use returned number as spc-N (create issue before Spec file)." >&2
echo "  Local claim is for tests / explicit offline degrade only (multi-clone unsafe)." >&2

PREFIX="spc-"
SUBDIR="specs"
SCAN_DIRS=("$HOME_DIR/$SUBDIR")
if [[ -n "$ROOT" ]]; then
  SCAN_DIRS+=("$ROOT/docs/design")
fi
MAIN_ROOT="${LATTICE_MAIN_ROOT:-}"
if [[ -n "$MAIN_ROOT" && "$HOME_DIR" != "$MAIN_ROOT/.lattice" ]]; then
  SCAN_DIRS+=("$MAIN_ROOT/.lattice/$SUBDIR")
fi

if $HOME_EXPLICIT; then
  CLAIM_DIR="$HOME_DIR/.ids"
else
  CLAIM_HOME=$(lattice_claim_home 2>/dev/null || echo "$HOME_DIR")
  CLAIM_DIR="$CLAIM_HOME/.ids"
fi
SCAN_DIRS+=("$CLAIM_DIR")
if [[ "$CLAIM_DIR" != "$HOME_DIR/.ids" ]]; then
  SCAN_DIRS+=("$HOME_DIR/.ids")
fi

scan_max() {
  local max=0 dir path base n
  for dir in "${SCAN_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' path; do
      base=$(basename "$path")
      if [[ "$base" =~ ^${PREFIX}([0-9]+)([-.]|$) ]]; then
        n=$((10#${BASH_REMATCH[1]}))
        if (( n > max )); then max=$n; fi
      fi
    done < <(find "$dir" -maxdepth 1 \( -name "${PREFIX}*" \) -print0 2>/dev/null || true)
  done
  printf '%d' "$max"
}

MAX=$(scan_max)
NEXT=$((MAX + 1))

if $CLAIM; then
  mkdir -p "$CLAIM_DIR"
  for _ in $(seq 1 100); do
    if mkdir "$CLAIM_DIR/${PREFIX}${NEXT}" 2>/dev/null; then
      printf '%d\n' "$NEXT"
      exit 0
    fi
    MAX=$(scan_max)
    NEXT=$((MAX + 1))
  done
  echo "Error: could not claim a spc id after 100 attempts" >&2
  exit 1
fi

printf '%d\n' "$NEXT"
