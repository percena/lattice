#!/usr/bin/env bash
# lineage-metrics.sh — L1 running-data metrics for review-lineage (spc-369 A1).
#
# Computes, from `.lattice/` + `git` only (no network), the numbers the audit
# rev-20260902-015425Z F1 counted by hand — status histogram, ledger coverage,
# walked vs never-walked edges, direct jumps, fix-cycle distribution, side
# states / wait reasons, binder section usage, `- NOTICED:` backlog, escape
# traces by rule_id, base-branch commit mix, Spec bloodline drift — writes a
# schema-versioned JSON snapshot and prints a Markdown delta vs the previous.
#
# Usage:
#   lineage-metrics.sh [--home <path>] [--since <ref|ISO|Nd>] [--base <branch>]
#                      [--snapshot-dir <dir>] [--json|--md] [--no-snapshot]
#
#   --home          lattice home (default: <git toplevel>/.lattice)
#   --since         git window: `30d` (default) | ISO date | a ref (ref..base)
#   --base          integration branch (default: resolve-integration-branch.sh
#                   answer, else dev/develop/main/master detection)
#   --snapshot-dir  where snapshots live (default: <home>/reviews/metrics)
#   --json          print the metrics + delta as JSON (default: --md)
#   --md            print the Markdown delta report
#   --no-snapshot   compute + print only; write nothing
#
# Writes <snapshot-dir>/lineage-<YYYYMMDD-HHMMSSZ>.json unless --no-snapshot.
# Exit: 0 ok · 1 python3/_lattice-lib unavailable · 2 usage.
#
# _lattice-lib resolves through resolve-lattice-lib.sh (the sibling install
# dir is the trust anchor; LATTICE_LIB_SCRIPTS is the explicit override) —
# never the consumer cwd (skill-anatomy rule 1).
set -euo pipefail

HOME_DIR=""
SINCE="30d"
BASE=""
SNAP_DIR=""
MODE="md"
WRITE_SNAPSHOT=true
CREATED_AFTER=""

usage() {
  cat >&2 <<'EOF'
Usage: lineage-metrics.sh [--home <path>] [--since <ref|ISO|Nd>] [--base <branch>]
                          [--snapshot-dir <dir>] [--json|--md] [--no-snapshot]
                          [--created-after <YYYY-MM-DD>]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) [[ $# -ge 2 ]] || usage; HOME_DIR="$2"; shift 2 ;;
    --since) [[ $# -ge 2 ]] || usage; SINCE="$2"; shift 2 ;;
    --base) [[ $# -ge 2 ]] || usage; BASE="$2"; shift 2 ;;
    --snapshot-dir) [[ $# -ge 2 ]] || usage; SNAP_DIR="$2"; shift 2 ;;
    --created-after) [[ $# -ge 2 ]] || usage; CREATED_AFTER="$2"; shift 2 ;;
    --json) MODE="json"; shift ;;
    --md) MODE="md"; shift ;;
    --no-snapshot) WRITE_SNAPSHOT=false; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

# --- Resolve _lattice-lib (trust anchor: the resolver's own install dir) ------
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

# --- python3 (stdlib only) — degrade with the platform install hint ----------
if ! bash "$LIB/ensure-python3.sh"; then
  echo "lineage-metrics: unavailable — python3 is required (see the install hint above)." >&2
  exit 1
fi

# --- Lattice home + repo root -------------------------------------------------
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

# --- Integration branch: explicit --base > resolver > python detection -------
if [[ -z "$BASE" && -f "$LIB/resolve-integration-branch.sh" ]]; then
  BASE=$(bash "$LIB/resolve-integration-branch.sh" --repo-root "$REPO_ROOT" --json 2>/dev/null \
    | sed -n 's/^[[:space:]]*"recommended_base":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)
fi

export LM_HOME="$HOME_DIR"
export LM_REPO_ROOT="$REPO_ROOT"
export LM_SINCE="$SINCE"
export LM_BASE="$BASE"
export LM_SNAP_DIR="$SNAP_DIR"
export LM_MODE="$MODE"
export LM_WRITE="$WRITE_SNAPSHOT"
export LM_LIB="$LIB/lib"
export LM_SELF_LIB="$SCRIPT_DIR/lib"
export LM_CREATED_AFTER="$CREATED_AFTER"

python3 - <<'PY'
import json, os, sys

sys.path.insert(0, os.environ["LM_LIB"])
sys.path.insert(0, os.environ["LM_SELF_LIB"])
import lineage_metrics as lm

home = os.environ["LM_HOME"]
root = os.environ["LM_REPO_ROOT"]
since = os.environ.get("LM_SINCE") or None
base = os.environ.get("LM_BASE") or None
snap_dir = os.environ["LM_SNAP_DIR"]
mode = os.environ["LM_MODE"]
write = os.environ.get("LM_WRITE", "true") == "true"
created_after = os.environ.get("LM_CREATED_AFTER") or None

cur = lm.collect(home, repo_root=root, since=since, base_branch=base, created_after=created_after)
prev = lm.load_previous(snap_dir)
d = lm.delta(cur, prev)
snapshot_file = lm.write_snapshot(snap_dir, cur) if write else None

if mode == "json":
    out = dict(cur)
    out["delta"] = d
    out["snapshot_file"] = snapshot_file
    print(json.dumps(out, indent=2, ensure_ascii=False))
else:
    print(lm.render_md(cur, d))
    if snapshot_file:
        print()
        print("_Snapshot written: `%s`_" % snapshot_file)
PY
