#!/usr/bin/env bash
# hotspot-metrics.sh — L4 synthesis sensor for review-lineage (spc-387 A1).
#
# Computes cross-cutting recurrence: hotspot clusters (files grouped by
# path/skill/stage), fix-class histogram, ticket genealogy, cross-audit
# recurrence, NOTICED feedback. Writes a schema-versioned JSON snapshot
# and prints a Markdown report.
#
# Usage:
#   hotspot-metrics.sh [--home <path>] [--since <ref|ISO|Nd>] [--base <branch>]
#                      [--snapshot-dir <dir>] [--json|--md] [--no-snapshot]
#
#   --home          lattice home (default: <git toplevel>/.lattice)
#   --since         git window: `30d` (default) | ISO date | a ref (ref..base)
#   --base          integration branch (default: resolve-integration-branch.sh
#                   answer, else dev/develop/main/master detection)
#   --snapshot-dir  where snapshots live (default: <home>/reviews/metrics)
#   --json          print the metrics as JSON
#   --md            print the Markdown report (default)
#   --no-snapshot   compute + print only; write nothing
#
# Writes <snapshot-dir>/hotspot-<YYYYMMDD-HHMMSSZ>.json unless --no-snapshot.
# Exit: 0 ok · 1 python3/_lattice-lib unavailable · 2 usage.
set -euo pipefail

HOME_DIR=""
SINCE="30d"
BASE=""
SNAP_DIR=""
MODE="md"
WRITE_SNAPSHOT=true

usage() {
  cat >&2 <<'EOF'
Usage: hotspot-metrics.sh [--home <path>] [--since <ref|ISO|Nd>] [--base <branch>]
                          [--snapshot-dir <dir>] [--json|--md] [--no-snapshot]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) [[ $# -ge 2 ]] || usage; HOME_DIR="$2"; shift 2 ;;
    --since) [[ $# -ge 2 ]] || usage; SINCE="$2"; shift 2 ;;
    --base) [[ $# -ge 2 ]] || usage; BASE="$2"; shift 2 ;;
    --snapshot-dir) [[ $# -ge 2 ]] || usage; SNAP_DIR="$2"; shift 2 ;;
    --json) MODE="json"; shift ;;
    --md) MODE="md"; shift ;;
    --no-snapshot) WRITE_SNAPSHOT=false; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

# --- Resolve _lattice-lib -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RESOLVE="$SCRIPT_DIR/../../_lattice-lib/scripts/resolve-lattice-lib.sh"
if [[ ! -f "$RESOLVE" ]]; then
  echo "Error: _lattice-lib is not installed beside review-lineage ($RESOLVE missing)" >&2
  exit 1
fi
LIB=$(bash "$RESOLVE")
for helper in lib/queue_health.py lib/transition_table.py ensure-python3.sh; do
  if [[ ! -f "$LIB/$helper" ]]; then
    echo "Error: $helper missing from _lattice-lib at $LIB" >&2
    exit 1
  fi
done

# --- python3 (stdlib only) ------------------------------------------------
if ! bash "$LIB/ensure-python3.sh"; then
  echo "hotspot-metrics: unavailable — python3 is required." >&2
  exit 1
fi

# --- Lattice home + repo root ---------------------------------------------
if [[ -z "$HOME_DIR" ]]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  HOME_DIR="$ROOT/.lattice"
fi
if [[ ! -d "$HOME_DIR" ]]; then
  echo "Error: lattice home not found: $HOME_DIR" >&2
  exit 1
fi
HOME_DIR="$(cd "$HOME_DIR" && pwd -P)"
REPO_ROOT=$(git -C "$(dirname "$HOME_DIR")" rev-parse --show-toplevel 2>/dev/null || dirname "$HOME_DIR")
[[ -n "$SNAP_DIR" ]] || SNAP_DIR="$HOME_DIR/reviews/metrics"

# --- Integration branch ---------------------------------------------------
if [[ -z "$BASE" && -f "$LIB/resolve-integration-branch.sh" ]]; then
  BASE=$(bash "$LIB/resolve-integration-branch.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null \
    | sed -n 's/^[[:space:]]*"recommended_base":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
fi

export HM_HOME="$HOME_DIR"
export HM_REPO_ROOT="$REPO_ROOT"
export HM_SINCE="$SINCE"
export HM_BASE="$BASE"
export HM_SNAP_DIR="$SNAP_DIR"
export HM_MODE="$MODE"
export HM_WRITE="$WRITE_SNAPSHOT"
export HM_LIB="$LIB/lib"
export HM_SELF_LIB="$SCRIPT_DIR/lib"

python3 - <<'PY'
import json, os, sys

sys.path.insert(0, os.environ["HM_LIB"])
sys.path.insert(0, os.environ["HM_SELF_LIB"])
import hotspot_metrics as hm

home = os.environ["HM_HOME"]
root = os.environ["HM_REPO_ROOT"]
since = os.environ.get("HM_SINCE") or None
base = os.environ.get("HM_BASE") or None
snap_dir = os.environ["HM_SNAP_DIR"]
mode = os.environ["HM_MODE"]
write = os.environ.get("HM_WRITE", "true") == "true"

cur = hm.collect(home, repo_root=root, since=since, base_branch=base)
prev = hm.load_previous(snap_dir) if write else None
snapshot_file = hm.write_snapshot(snap_dir, cur) if write else None

if mode == "json":
    out = dict(cur)
    if prev:
        out["previous"] = prev
    out["snapshot_file"] = snapshot_file
    print(json.dumps(out, indent=2, ensure_ascii=False))
else:
    print(hm.render_md(cur, prev))
    if snapshot_file:
        print()
        print("_Snapshot written: `%s`_" % snapshot_file)
PY
