#!/usr/bin/env bash
# Queue-health water-level sensor (spc-186 A5, ADR-007 §8).
#
# Advisory-only staleness surfacing — never a HARD block (ADR-007 §8 boundary
# sensor family). Eliminates the silent-degradation channel: pr-open piles up
# silently when triage is skipped; deferred/stuck/parked have no water-level.
#
# Two surfaces (same data, different verbosity):
#   --banner   one-line water-level for start-work entry (empty when clean)
#   --section  detailed "Queue health" block for the review-delivery digest
#   --json     machine-readable (for tests / programmatic consumers)
#
# Age computation (tkt-191 dependency): binder `updated` field is the primary
# source (bumped atomically on each status transition). For pr-open binders
# predating the row (lazy migration), fall back to `gh pr view <N> --json
# createdAt` (the PR openedAt — a faithful proxy, since stamp-pr-open runs
# right after gh pr create). Side-state binders without `updated` report age
# "unknown" (no gh fallback — batch-work / spec-supersede stamped them, not gh).
#
# Thresholds live in .lattice/config.yaml under `queue_health:` (pr_open_hours,
# side_state_total); defaults pr-open > 36h, side-states > 5. Tunable.
#
# Usage:
#   queue-health.sh [--banner|--section|--json] [--home <path>] [--no-gh]
#
# Exit: 0 always (advisory sensor — never blocks). 2 on usage.
set -euo pipefail

MODE="banner"
HOME_DIR=""
USE_GH=true

usage() {
  cat >&2 <<'EOF'
Usage: queue-health.sh [--banner|--section|--json] [--home <path>] [--no-gh]

  --banner   one-line water-level summary (start-work entry; empty when clean)
  --section  detailed "Queue health" block (review-delivery digest)
  --json     machine-readable JSON
  --home     lattice home (default: .lattice at repo root)
  --no-gh    skip the gh pr createdAt fallback (side-state ages still computed)
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --banner) MODE="banner"; shift ;;
    --section) MODE="section"; shift ;;
    --json) MODE="json"; shift ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    --no-gh) USE_GH=false; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

# Advisory sensor — never blocks (spc-212 A2/D3 degrade path). If python3 is
# absent, emit a mode-appropriate empty/degraded result instead of a bare
# "command not found" mid-sensor.
if ! command -v python3 >/dev/null 2>&1; then
  case "$MODE" in
    banner) ;;                                  # silent empty banner
    section) echo "Queue health: unavailable (python3 missing — install per ensure-python3.sh)." ;;
    json)   echo '{}' ;;
  esac
  exit 0
fi

# Resolve lattice home (same priority as ci-gate-check.sh / alignment-check.sh).
if [[ -z "$HOME_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LIB_SCRIPTS=""
  for cand in \
    "${LATTICE_LIB_SCRIPTS:-}" \
    "${SCRIPT_DIR}" \
    "${SCRIPT_DIR}/../../_lattice-lib/scripts"
  do
    [[ -n "$cand" && -f "$cand/_lattice-home.sh" ]] || continue
    LIB_SCRIPTS="$cand"
    break
  done
  if [[ -n "$LIB_SCRIPTS" && -f "$LIB_SCRIPTS/_lattice-home.sh" ]]; then
    # shellcheck source=/dev/null
    source "$LIB_SCRIPTS/_lattice-home.sh"
    lattice_export_roots 2>/dev/null || true
    HOME_DIR=$(lattice_default_home 2>/dev/null || echo "")
  fi
fi
if [[ -z "$HOME_DIR" ]]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  HOME_DIR="${LATTICE_HOME:-$ROOT/.lattice}"
fi

TICKETS_DIR="$HOME_DIR/tickets"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

export QH_HOME="$HOME_DIR"
export QH_TICKETS="$TICKETS_DIR"
export QH_MODE="$MODE"
export QH_LIB="$LIB_DIR"
export QH_USE_GH="$USE_GH"
export QH_GH_AVAILABLE=false
if $USE_GH && command -v gh >/dev/null 2>&1; then
  export QH_GH_AVAILABLE=true
fi

python3 - <<'PY'
import datetime, json, os, subprocess, sys

sys.path.insert(0, os.environ["QH_LIB"])
import queue_health as qh

home = os.environ["QH_HOME"]
tickets = os.environ["QH_TICKETS"]
mode = os.environ["QH_MODE"]
gh_available = os.environ.get("QH_GH_AVAILABLE", "false").lower() == "true"

now = datetime.datetime.now(datetime.timezone.utc)
thresholds = qh.load_thresholds(home)

# gh pr createdAt fallback for pr-open binders predating the `updated` row
# (lazy migration — tkt-191). Side-state binders have no gh fallback.
def gh_opened_at(pr_n):
    if not gh_available:
        return None
    try:
        out = subprocess.check_output(
            ["gh", "pr", "view", str(pr_n), "--json", "createdAt"],
            text=True, stderr=subprocess.DEVNULL, timeout=15,
        )
        d = json.loads(out)
        return d.get("createdAt") or None
    except Exception:
        return None

data = qh.scan_binders(tickets, now=now, gh_fallback=gh_opened_at)

if mode == "json":
    print(json.dumps({
        "thresholds": thresholds,
        "scanned": data["scanned"],
        "side_state_total": data["side_state_total"],
        "side_states": data["side_states"],
        "pr_open": data["pr_open"],
    }, indent=2))
elif mode == "banner":
    banner = qh.format_banner(data, thresholds)
    if banner:
        print(banner)
elif mode == "section":
    print(qh.format_section(data, thresholds))
PY
