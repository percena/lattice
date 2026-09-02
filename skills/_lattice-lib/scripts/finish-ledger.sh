#!/usr/bin/env bash
# Stamp a ticket binder's `## Finish` ledger with firm GitHub dates + prs + status.
# Called by finish-work AFTER merge + cleanup, on the merge-base branch.
#
# Idempotent: re-running for the same PR updates the existing pr-N line; never
# creates a second `## Finish` heading. No-op + note when the binder is missing
# (ticket-only flow without a binder) — does NOT fail finish.
#
# Usage:
#   finish-ledger.sh --pr <N> [--issue <M>] --binder <path> [--repo <owner/repo>]
#   Exits 0 on success or no-binder-skip; 1 on gh/IO failure.
set -euo pipefail

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
bash "$(dirname "${BASH_SOURCE[0]}")/ensure-python3.sh" || exit 1

PR_N=""
ISSUE_M=""
BINDER=""
REPO=""
MERGED_AT_OVERRIDE=""
CLOSED_AT_OVERRIDE=""
PR_STATE_OVERRIDE=""
CANCEL=false
REASON=""

usage() {
  cat >&2 <<'EOF'
Usage: finish-ledger.sh --pr <N> [--issue <M>] --binder <path> [--repo <owner/repo>]
                        [--merged-at <ts>] [--closed-at <ts>] [--pr-state MERGED|CLOSED]
  --pr        PR number (required for the PR path). Fetches mergedAt unless --merged-at given.
  --issue     closing issue number (optional). Fetches closedAt; sets status=closed.
  --binder    path to binder README.md (required).
  --repo      owner/repo for gh (optional; defaults to origin).
  --merged-at override mergedAt (skip gh fetch; tests/offline).
  --closed-at override closedAt (skip gh fetch).
  --pr-state  override PR state MERGED|CLOSED (skip gh fetch).

Cancel path (no PR; terminal human cancel before any PR):
  finish-ledger.sh --cancel --reason "<text>" (--closed-at <ts> | --issue <M>)
                   --binder <path> [--repo <owner/repo>]
  --cancel      no-PR terminal cancel. Requires --reason and either --closed-at
                (human-supplied firm close time) or --issue (gh-verified CLOSED).
                Writes a dated cancel ledger line; never claims mergedAt or a PR row.
  --reason      human-supplied cancel reason (required with --cancel).
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR_N="${2:-}"; shift 2 ;;
    --issue) ISSUE_M="${2:-}"; shift 2 ;;
    --binder) BINDER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --merged-at) MERGED_AT_OVERRIDE="${2:-}"; shift 2 ;;
    --closed-at) CLOSED_AT_OVERRIDE="${2:-}"; shift 2 ;;
    --pr-state) PR_STATE_OVERRIDE=$(printf '%s' "${2:-}" | tr '[:lower:]' '[:upper:]'); shift 2 ;;
    --cancel) CANCEL=true; shift ;;
    --reason) REASON="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if $CANCEL; then
  [[ -n "$PR_N" ]] && { echo "Error: --cancel is a no-PR path; use --pr-state CLOSED for a closed-without-merge PR" >&2; exit 2; }
  [[ -n "$PR_STATE_OVERRIDE" || -n "$MERGED_AT_OVERRIDE" ]] && { echo "Error: --cancel is a no-PR path; --pr-state/--merged-at are not valid here" >&2; exit 2; }
  [[ -z "$REASON" ]] && { echo "Error: --cancel requires --reason \"<text>\"" >&2; exit 2; }
  if [[ -z "$CLOSED_AT_OVERRIDE" && -z "$ISSUE_M" ]]; then
    echo "Error: --cancel requires terminal evidence: --closed-at <ts> (human-supplied) or --issue <M> (gh-verified CLOSED)" >&2
    exit 2
  fi
else
  [[ -z "$PR_N" ]] && { echo "Error: --pr is required" >&2; usage; }
fi
[[ -z "$BINDER" ]] && { echo "Error: --binder is required" >&2; usage; }

# `gh pr view <arg>` accepts a number, a branch name OR a full URL, and gh's
# flag parser accepts `--repo=owner/name` in positional position. Identifiers
# here are agent-derived (from PR/issue prose), so a pasted URL would stamp
# another repository's mergedAt/closedAt into this repo's binder. Same rule the
# sibling helpers already enforce (cleanup-workspace.sh, update-pr-base.sh,
# alignment-check.sh).
if ! $CANCEL && [[ ! "$PR_N" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --pr must be a positive GitHub PR number, got: $PR_N" >&2
  exit 2
fi
if [[ -n "$ISSUE_M" && ! "$ISSUE_M" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --issue must be a positive GitHub issue number, got: $ISSUE_M" >&2
  exit 2
fi
# owner/repo becomes a path segment in a gh api URL. Each component must
# contain at least one non-dot character, which is what rejects the traversal
# forms `..`, `.` and `...` while still allowing real names like `owner/.github`.
OWNER_REPO_RE='^[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*$'
if [[ -n "$REPO" && ! "$REPO" =~ $OWNER_REPO_RE ]]; then
  echo "Error: --repo must be owner/name, got: $REPO" >&2
  exit 2
fi

GH_ARGS=()
[[ -n "$REPO" ]] && GH_ARGS+=(--repo "$REPO")

# --- No binder ⇒ skip + note (not a failure) ---------------------------------
if [[ ! -f "$BINDER" ]]; then
  echo "finish-ledger: no binder at $BINDER — skip (ticket-only flow)"
  exit 0
fi

# This script truncates and rewrites $BINDER. The path is agent-derived, and a
# cloned repo can ship `.lattice/tickets/tkt-1-x/README.md` as a symlink to
# anything. Contain it the way upload-github-asset.sh contains its source:
# resolve, refuse symlinked components, require a regular file under the
# repo's .lattice/ tree. Deliberately no env escape hatch: an opt-out would
# be the first thing a crafted binder path tried to set.
BINDER_REPO_ROOT=$(git -C "$(dirname "$BINDER")" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$BINDER_REPO_ROOT" ]]; then
  echo "Error: --binder is not inside a git worktree: $BINDER" >&2
  exit 1
fi
if ! BINDER=$(LEDGER_BINDER="$BINDER" LEDGER_ROOT="$BINDER_REPO_ROOT" python3 - <<'LEDGERPATH'
import os, stat, sys

binder = os.path.abspath(os.environ["LEDGER_BINDER"])
root = os.path.realpath(os.environ["LEDGER_ROOT"])
home = os.path.join(root, ".lattice")

# lstat every component below the repo root so no ancestor can redirect.
anchor, candidate = None, binder
while True:
    if os.path.realpath(candidate) == root:
        anchor = candidate
        break
    parent = os.path.dirname(candidate)
    if parent == candidate:
        break
    candidate = parent

components = [binder]
if anchor is not None:
    components, current = [], anchor
    for part in os.path.relpath(binder, anchor).split(os.path.sep):
        current = os.path.join(current, part)
        components.append(current)

for component in components:
    try:
        mode = os.lstat(component).st_mode
    except FileNotFoundError:
        print(f"Error: binder not found: {binder}", file=sys.stderr)
        raise SystemExit(1)
    if stat.S_ISLNK(mode):
        print(f"Error: refusing symlinked binder path component: {component}", file=sys.stderr)
        raise SystemExit(1)

resolved = os.path.realpath(binder)
if os.path.commonpath([home, resolved]) != home:
    print(f"Error: binder must live under {home}, got: {resolved}", file=sys.stderr)
    raise SystemExit(1)
if not stat.S_ISREG(os.stat(resolved).st_mode):
    print(f"Error: binder is not a regular file: {resolved}", file=sys.stderr)
    raise SystemExit(1)
print(resolved)
LEDGERPATH
); then
  exit 1
fi

# --- Repo identity binding ----------------------------------------------------
# The binder lives in THIS repo, but `gh` resolves the PR against --repo or the
# current directory's repo. If those are different repositories, the ledger
# would record a foreign PR's dates as this ticket's outcome. Only enforceable
# (and only needed) when gh is actually consulted.
repo_identity_from_url() {
  python3 - "$1" <<'PY'
import re, sys
from urllib.parse import urlsplit

raw = sys.argv[1].strip()
host = path = ""
if "://" in raw:
    parsed = urlsplit(raw)
    host = parsed.hostname or ""
    if parsed.port:
        host += f":{parsed.port}"
    path = parsed.path
else:
    match = re.match(r"^(?:[^@/]+@)?([^:/]+):(.+)$", raw)
    if match:
        host, path = match.groups()

path = path.strip("/")
if path.endswith(".git"):
    path = path[:-4]
parts = path.split("/")
if not host or len(parts) != 2 or not all(parts):
    raise SystemExit(1)
print(f"{host}/{parts[0]}/{parts[1]}".lower())
PY
}

# What actually needs a gh round-trip:
#   PR outcome  — hard requirement unless fully overridden (cancel path has no PR)
#   issue state — best effort; an unreachable issue records "not closed"
NEED_GH_PR=true
if $CANCEL; then
  NEED_GH_PR=false
elif [[ -n "$PR_STATE_OVERRIDE" ]]; then
  # A CLOSED PR carries no mergedAt, so it needs nothing else.
  [[ "$PR_STATE_OVERRIDE" != "MERGED" || -n "$MERGED_AT_OVERRIDE" ]] && NEED_GH_PR=false
elif [[ -n "$MERGED_AT_OVERRIDE" ]]; then
  NEED_GH_PR=false   # back-compat: an explicit --merged-at means MERGED
fi
NEED_GH_ISSUE=false
[[ -n "$ISSUE_M" && -z "$CLOSED_AT_OVERRIDE" ]] && NEED_GH_ISSUE=true

BINDER_ORIGIN=$(git -C "$BINDER_REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)
BINDER_REPO_ID=$(repo_identity_from_url "$BINDER_ORIGIN" 2>/dev/null || true)

GH_USABLE=false
GH_TARGET_REPO_ID=""
if { $NEED_GH_PR || $NEED_GH_ISSUE; } && command -v gh >/dev/null 2>&1; then
  if [[ -n "$REPO" && -n "$BINDER_REPO_ID" ]]; then
    BINDER_HOST=${BINDER_REPO_ID%%/*}
    TARGET_HOST=${GH_HOST:-$BINDER_HOST}
    GH_TARGET_REPO_ID=$(printf '%s/%s' "$TARGET_HOST" "$REPO" | tr '[:upper:]' '[:lower:]')
    # Pin the same host in the actual gh query. Bare owner/repo can otherwise
    # resolve through the caller's cwd/default host while the binder belongs to
    # a GHES origin, defeating the identity comparison above.
    GH_ARGS=(--repo "$TARGET_HOST/$REPO")
  else
    GH_TARGET_URL=$(gh repo view --json url -q '.url' 2>/dev/null || true)
    GH_TARGET_REPO_ID=$(repo_identity_from_url "$GH_TARGET_URL" 2>/dev/null || true)
  fi
  if [[ -n "$GH_TARGET_REPO_ID" && -n "$BINDER_REPO_ID" && "$BINDER_REPO_ID" != "$GH_TARGET_REPO_ID" ]]; then
    # Always fatal: a foreign PR's dates must never be stamped here, even when
    # only the (soft) issue lookup wanted gh.
    echo "Error: refusing to stamp GitHub state from a different repository into this binder" >&2
    echo "  binder repo: $BINDER_REPO_ID" >&2
    echo "  gh target:   $GH_TARGET_REPO_ID" >&2
    exit 1
  fi
  [[ -n "$GH_TARGET_REPO_ID" && -n "$BINDER_REPO_ID" ]] && GH_USABLE=true
fi

if $NEED_GH_PR && ! $GH_USABLE; then
  echo "Error: cannot resolve PR #$PR_N against this binder's repository" >&2
  echo "  the binder's repo and the gh target must both be known and identical" >&2
  echo "  binder repo: ${BINDER_REPO_ID:-(unresolved origin)} at $BINDER_REPO_ROOT" >&2
  echo "  gh target:   ${GH_TARGET_REPO_ID:-(unknown)}" >&2
  echo "  pass --repo owner/name, or --pr-state/--merged-at for an offline stamp" >&2
  exit 1
fi

# --- Resolve PR outcome (one query; overrides skip gh for tests/offline) ------
ISO8601_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$'

PR_STATE="$PR_STATE_OVERRIDE"
MERGED_AT="$MERGED_AT_OVERRIDE"
PR_URL=""

if $NEED_GH_PR; then
  PR_JSON=$(gh pr view "$PR_N" ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json state,mergedAt,url 2>/dev/null || true)
  if [[ -z "$PR_JSON" ]]; then
    echo "Error: could not read PR #$PR_N (gh auth? wrong repo?)" >&2
    exit 1
  fi
  # One parse, three values; keeps state and dates from disagreeing across calls.
  eval "$(printf '%s' "$PR_JSON" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
def emit(name, value):
    normalized = "" if value is None else str(value)
    print(f"{name}={shlex.quote(normalized)}")
emit("GH_PR_STATE", d.get("state") or "")
emit("GH_PR_MERGED_AT", d.get("mergedAt") or "")
emit("GH_PR_URL", d.get("url") or "")
')"
  [[ -z "$PR_STATE" ]] && PR_STATE="$GH_PR_STATE"
  [[ -z "$MERGED_AT" ]] && MERGED_AT="$GH_PR_MERGED_AT"
  PR_URL="$GH_PR_URL"
elif [[ -n "$REPO" ]]; then
  BINDER_HOST=${BINDER_REPO_ID%%/*}
  OFFLINE_HOST=${GH_HOST:-${BINDER_HOST:-github.com}}
  PR_URL="https://$OFFLINE_HOST/$REPO/pull/$PR_N"
fi

# --merged-at without --pr-state means "this PR merged" (back-compat).
[[ -z "$PR_STATE" && -n "$MERGED_AT" ]] && PR_STATE="MERGED"

# Cancel path has no PR; skip PR-state validation entirely (no fabricated PR row).
if ! $CANCEL; then
  case "$PR_STATE" in
    MERGED)
      # `gh -q .mergedAt` prints the literal string "null" for an unmerged PR,
      # which is non-empty and would be stamped verbatim as a merge date.
      if [[ ! "$MERGED_AT" =~ $ISO8601_RE ]]; then
        echo "Error: PR #$PR_N is MERGED but mergedAt is not an ISO-8601 timestamp: ${MERGED_AT:-(empty)}" >&2
        exit 1
      fi
      ;;
    CLOSED)
      # Documented contract (finish-work SKILL.md): a close-without-merge records
      # status WITHOUT claiming mergedAt. Never carry a stale/omitted date here.
      MERGED_AT=""
      ;;
    OPEN)
      echo "Error: PR #$PR_N is still OPEN; finish-ledger records the outcome AFTER merge or close" >&2
      exit 1
      ;;
    *)
      echo "Error: unknown PR state for #$PR_N: ${PR_STATE:-(empty)}" >&2
      exit 1
      ;;
  esac
fi

# --- Resolve closing issue state ---------------------------------------------
CLOSED_AT="$CLOSED_AT_OVERRIDE"
ISSUE_CLOSED=false
GH_ISSUE_STATE_REASON=""
if [[ -n "$ISSUE_M" ]]; then
  if [[ -n "$CLOSED_AT_OVERRIDE" ]]; then
    ISSUE_CLOSED=true
  elif $GH_USABLE; then
    ISSUE_JSON=$(gh issue view "$ISSUE_M" ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json state,closedAt 2>/dev/null || true)
    if [[ -n "$ISSUE_JSON" ]]; then
      eval "$(printf '%s' "$ISSUE_JSON" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
def emit(name, value):
    normalized = "" if value is None else str(value)
    print(f"{name}={shlex.quote(normalized)}")
emit("GH_ISSUE_STATE", d.get("state") or "")
emit("GH_ISSUE_CLOSED_AT", d.get("closedAt") or "")
')"
      CLOSED_AT="$GH_ISSUE_CLOSED_AT"
      [[ "$GH_ISSUE_STATE" == "CLOSED" ]] && ISSUE_CLOSED=true
      # state_reason is not a gh issue view --json field on all gh versions
      # (tkt-294). Fetch via REST for ledger fidelity + anomaly detection.
      # GH_TARGET_REPO_ID is host/owner/repo (e.g. github.com/percena/lattice)
      # — strip the host prefix for the gh api repos/ path (needs owner/repo).
      # GH_TARGET_REPO_ID is set in both the --repo path and the auto-resolve
      # path; $REPO alone is empty without --repo (tkt-301 code review).
      # Surface fetch failures so a close-reason contradiction is not silently
      # lost when the API is least reliable (rate limits, auth, cross-repo).
      if [[ "$GH_ISSUE_STATE" == "CLOSED" && -n "$GH_TARGET_REPO_ID" ]]; then
        API_REPO="${GH_TARGET_REPO_ID#*/}"  # strip host → owner/repo
        API_HOST="${GH_TARGET_REPO_ID%%/*}"  # host for --hostname (tkt-311 A1)
        if ! GH_ISSUE_STATE_REASON=$(gh api "repos/${API_REPO}/issues/${ISSUE_M}" --jq '.state_reason' ${API_HOST:+--hostname "$API_HOST"} 2>/dev/null); then
          GH_ISSUE_STATE_REASON=""
          echo "finish-ledger: WARNING — cannot fetch state_reason for issue #$ISSUE_M (REST API failed); close-reason not recorded in ledger" >&2
        fi
        # Defense-in-depth: gh api --jq may emit 'null' (issue lacks state_reason)
        # or an error body on non-2xx — discard anything not in the known set.
        case "$GH_ISSUE_STATE_REASON" in
          completed|not_planned|reopened|duplicate|out_of_date) ;;
          *) GH_ISSUE_STATE_REASON="" ;;
        esac
      fi
    fi
  fi
  # Same "null"-string trap as mergedAt: an OPEN issue reports null.
  if [[ -n "$CLOSED_AT" && ! "$CLOSED_AT" =~ $ISO8601_RE ]]; then
    echo "finish-ledger: WARNING — closedAt for issue #$ISSUE_M is not a timestamp ($CLOSED_AT); recording as not closed" >&2
    CLOSED_AT=""
    ISSUE_CLOSED=false
  fi
  $ISSUE_CLOSED || CLOSED_AT=""
fi

# ISO-8601 validation for CLOSED_AT that runs for BOTH the cancel path and the
# issue path (tkt-179 A3): the only prior check was inside the ISSUE_M block, so
# the no-issue cancel path bypassed it and garbage values were stamped verbatim.
if [[ -n "$CLOSED_AT" && ! "$CLOSED_AT" =~ $ISO8601_RE ]]; then
  echo "Error: --closed-at must be an ISO-8601 timestamp, got: $CLOSED_AT" >&2
  exit 1
fi

# Cancel path: terminal evidence is mandatory. An OPEN/unverifiable issue is not
# a cancel — fail closed rather than strand the binder in a working state or
# stamp a fabricated terminal. A no-issue cancel already required --closed-at.
if $CANCEL && [[ -n "$ISSUE_M" ]] && ! $ISSUE_CLOSED; then
  echo "Error: --cancel requires terminal evidence — issue #$ISSUE_M is not closed (or could not be verified against this binder's repo)" >&2
  echo "  pass --closed-at <ts> for a human-supplied firm close time, or close the issue first" >&2
  exit 1
fi

# Issue URL base for the cancel path (no PR URL is available there). Falls back
# to the placeholder when neither --repo nor a resolved gh target is known.
ISSUE_BASE=""
if [[ -n "$ISSUE_M" ]]; then
  if [[ -n "$REPO" ]]; then
    BINDER_HOST=${BINDER_REPO_ID%%/*}
    OFFLINE_HOST=${GH_HOST:-${BINDER_HOST:-github.com}}
    ISSUE_BASE="https://$OFFLINE_HOST/$REPO"
  elif [[ -n "$GH_TARGET_REPO_ID" ]]; then
    ISSUE_BASE="https://$GH_TARGET_REPO_ID"
  fi
fi

# --- Stamp the binder (idempotent) --------------------------------------------
BINDER_ROWS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
STAMP_OUT=$(BINDER_ROWS_LIB="$BINDER_ROWS_LIB" python3 - "$BINDER" "$PR_N" "$MERGED_AT" "$CLOSED_AT" "$ISSUE_CLOSED" "$PR_URL" "$ISSUE_M" "$PR_STATE" "$CANCEL" "$REASON" "$ISSUE_BASE" "$GH_ISSUE_STATE_REASON" <<'PY'
import sys, re, os, stat, fcntl, datetime, importlib.util

sys.path.insert(0, os.environ["BINDER_ROWS_LIB"])
import binder_rows
import status_vocab
# spc-297: import transition-api for in-lock single-write atomicity.
_ta_path = os.path.join(os.environ["BINDER_ROWS_LIB"], "..", "transition-api.py")
_ta_spec = importlib.util.spec_from_file_location("transition_api", _ta_path)
_ta = importlib.util.module_from_spec(_ta_spec); _ta_spec.loader.exec_module(_ta)

binder, pr_n, merged_at, closed_at, issue_closed, pr_url, issue_m, pr_state, cancel, reason, issue_base, state_reason = sys.argv[1:13]
# `updated` field-table stamp (spc-186 A4 / tkt-191): bumped atomically with
# the status flip below, in this same locked transaction. Seconds-precision
# ISO-8601 UTC, matching the mergedAt/closedAt format the ledger records.
updated_stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
# Take an exclusive lock for the whole read-modify-write. Two finish sessions
# stamping the same binder for sibling PRs would otherwise both read the old
# content and the second rename would drop the first PR's line entirely.
# Lock the containing directory: its inode remains stable while the binder is
# atomically replaced, and unlike a sidecar lock it cannot be unlinked while a
# waiter still holds the old inode. It also leaves no untracked lock artifact.
lock_dir = os.path.dirname(os.path.abspath(binder)) or "."
lock_fd = os.open(lock_dir, os.O_RDONLY)
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
except OSError as exc:
    os.close(lock_fd)
    raise SystemExit(f"finish-ledger: cannot lock binder directory: {exc}")

# Read INSIDE the lock so a concurrent writer's line is already visible.
s = open(binder, encoding="utf-8").read()
orig = s

merged = pr_state == "MERGED"
cancel = cancel == "true"

# Capture the prior working status before any rewrite so an anomalous
# terminal-from-parked/stuck/deferred merge can be surfaced without stranding
# the binder (A2: merged outcomes preserve external truth and emit anomaly).
prior_status_match = re.search(r'\|\s*status\s*\|\s*(\S+)\s*\|', s)
prior_status = prior_status_match.group(1) if prior_status_match else ""

if cancel:
    # No-PR cancel: a dated cancel line, never a PR row or mergedAt claim.
    entry_line = f"- cancelled: {reason}"
    if closed_at:
        if not (issue_m and issue_closed == "true"):
            entry_line += f" — {closed_at}"
    elif issue_m and issue_closed == "true":
        # The issue is confirmed CLOSED but gh returned no closedAt (null).
        # Stamp a visible gap marker rather than a silent dateless cancel
        # line that reads like a clean cancel (tkt-242 L4). The status still
        # flips to closed — terminal evidence (issue closed) exists; only the
        # timestamp is missing.
        entry_line += f" — closedAt: unavailable (issue #{issue_m} CLOSED but closedAt null)"
    entry_pat = re.compile(r'^- cancelled: .*$', re.MULTILINE)
else:
    if merged:
        entry_line = f"- pr-{pr_n} merged: {merged_at}"
    else:
        entry_line = f"- pr-{pr_n} closed without merge"
    if pr_url:
        entry_line += f" — {pr_url}"
    entry_line += " (base merge)" if merged else ""
    entry_pat = re.compile(rf'^- pr-{re.escape(pr_n)} (?:merged:|closed without merge).*$', re.MULTILINE)

# Anomaly: a MERGED PR observed from a non-`pr-open` working state is
# unexpected provenance — external merge truth still wins (the binder flips to
# closed below), but the anomaly is recorded as ledger context rather than
# silently rewritten as a clean merge. Two classes (spc-337 A2 / ADR-012 §3):
#   side state (parked / stuck / deferred / rework): merged while parked;
#   direct jump (queued / in-progress): the in-progress / pr-open stamps were
#   skipped — the ledger edge carries metric `direct-jump` and this line makes
#   the skipped lifecycle visible in the binder itself.
anomaly_line = ""
if (not cancel) and merged and prior_status in {"parked", "stuck", "deferred", "rework"}:
    anomaly_line = f"\n- anomaly: prior status `{prior_status}` before terminal merge — external truth preserved"
elif (not cancel) and merged and prior_status in {"queued", "in-progress"}:
    anomaly_line = (f"\n- anomaly: direct jump — prior status `{prior_status}` before terminal merge; "
                    f"in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)")

issue_line = ""
if issue_m and closed_at and issue_closed == "true":
    base = ""
    if pr_url:
        base = pr_url.split("/pull/")[0]  # https://github.com/owner/repo
    elif issue_base:
        base = issue_base
    reason_suffix = f" (reason: {state_reason})" if state_reason else ""
    if base:
        issue_line = f"\n- issue #{issue_m} closed: {closed_at}{reason_suffix} — {base}/issues/{issue_m}"
    else:
        issue_line = f"\n- issue #{issue_m} closed: {closed_at}{reason_suffix} — https://github.com/<org>/<repo>/issues/{issue_m}"
elif issue_m and not issue_closed == "true" and not cancel:
    issue_line = f"\n- issue #{issue_m}: not closed (closed-without-merge? status recorded without mergedAt claim)"

# Anomaly: a Fixes issue closed as NOT_PLANNED/DUPLICATE/OUT_OF_DATE while a
# merged PR delivers it (tkt-294). The ledger already has an anomaly:
# vocabulary for unexpected states — this is the same class of surprise.
if (not cancel) and issue_m and issue_closed == "true" and state_reason and state_reason != "completed":
    anomaly_line += f"\n- anomaly: issue #{issue_m} closed as {state_reason.upper()} while PR #{pr_n} delivers it — reconcile close-reason vs delivery"

# 1. Replace `## Finish` body.
# Find the ## Finish section (up to next ## heading or EOF).
m = re.search(r'(^## Finish\s*\n)(.*?)(?=\n## |\Z)', s, flags=re.DOTALL | re.MULTILINE)
if not m:
    # No ## Finish heading — append one.
    s = s.rstrip() + "\n\n## Finish\n\n" + entry_line + anomaly_line + issue_line + "\n"
else:
    head, body = m.group(1), m.group(2)
    # Idempotent: if the entry already exists, update it; else append.
    if entry_pat.search(body):
        body = entry_pat.sub(entry_line, body)
        # refresh anomaly line if present
        if anomaly_line:
            anom_pat = re.compile(r'^- anomaly: .*$', re.MULTILINE)
            # Remove ALL existing anomaly lines first, then append the fresh
            # block. Without this, sub() replaces each of N existing lines with
            # the full multi-line anomaly_line, doubling on every re-stamp.
            body = anom_pat.sub('', body)
            body = re.sub(r'\n{3,}', '\n\n', body)  # collapse blanks from removal
            body = body.rstrip() + anomaly_line + "\n"
        # refresh issue line if issue info present
        if issue_line:
            iss_pat = re.compile(rf'^- issue #{re.escape(issue_m)}.*$', re.MULTILINE) if issue_m else None
            iss_m = iss_pat.search(body) if iss_pat else None
            if iss_m:
                # tkt-317 idempotency: a transient state_reason fetch failure makes
                # reason_suffix empty on a re-run. Always replace the line (so
                # closed_at / URL / not-closed state stay current); only the reason
                # suffix is PRESERVED from the existing line when the fresh fetch
                # lost it (never inject a reason into a "not closed" line).
                existing_match = iss_m.group(0)
                fresh_has_reason = " (reason:" in issue_line
                existing_has_reason = " (reason:" in existing_match
                if not fresh_has_reason and existing_has_reason and "not closed" not in issue_line:
                    m_reason = re.search(r' (\(reason: [^)]*\))', existing_match)
                    if m_reason:
                        issue_line = issue_line.replace(' — ', f'{m_reason.group(1)} — ', 1)
                body = iss_pat.sub(issue_line.lstrip("\n"), body)
            else:
                body = body.rstrip() + issue_line + "\n"
    else:
        # Drop a bare "(none yet)" placeholder.
        body = re.sub(r'^- \(none yet\)\s*\n?', '', body, flags=re.MULTILINE)
        body = body.rstrip()
        if body:
            body = body + "\n" + entry_line + anomaly_line + issue_line + "\n"
        else:
            body = "\n" + entry_line + anomaly_line + issue_line + "\n"
    s = s[:m.start()] + head + body + s[m.end():]

# 2. status: any working status → closed. spc-297: single-write atomicity —
#    the status flip + `updated` + ledger land in ONE `commit_transaction`
#    merged with the ## Finish body + prs row already in `s` (called inside
#    this dir lock). The prior is the REAL on-disk status (captured above);
#    prepare_commit_text's edge_for resolves the explicit terminal edge for
#    the prior status (pr-open→closed merge; queued|in-progress→closed
#    direct-jump; side-state→closed cancel/anomaly — spc-337 A2, no wildcard).
#    Idempotent re-runs (status already closed) do not flip — the
#    nonterminal-only guard skips them.

# 3. prs table row: canonical `pr-N — URL`, comma-joined for multiples —
# grammar single-sourced in lib/binder_rows.py (tkt-91). Placeholder variants
# are REPLACED, never appended beside (digest rev-20260826-172600Z Findings 4:
# appending left "(none) · pr-N …" rows, the tkt-43 duplication class); the
# legacy ` · ` joiner and bare `pr-N` (no URL) are never emitted — with no
# resolvable URL the row is left untouched and the gap is reported. The cancel
# path has no PR by construction, so it leaves the prs row untouched silently.
prs_row = re.compile(r'(\| prs \|)\s*(.*?)\s*(\|)')
m_prs = prs_row.search(s)
if m_prs:
    if not pr_url and not cancel:
        print("finish-ledger: WARNING — no PR URL resolved; prs row left untouched (bare pr-N is off-canon)", file=sys.stderr)
    elif pr_url:
        merged_row = binder_rows.merge_row(m_prs.group(2), pr_n, pr_url)
        s = prs_row.sub(lambda mm: f"{mm.group(1)} {merged_row} {mm.group(3)}", s, count=1)

flip_close = cancel or merged or issue_closed == "true"
close_reason = "merge" if (merged and not cancel) else "cancel"
TICKET_ID = ""
m_tid = re.match(r'^(tkt-[1-9][0-9]*)', os.path.basename(os.path.dirname(binder)))
if m_tid:
    TICKET_ID = m_tid.group(1)
do_flip = flip_close and prior_status and not status_vocab.is_terminal(prior_status)
written = False
flip_happened = False
if do_flip:
    rc, nt, entry = _ta.prepare_commit_text(s, TICKET_ID, "closed", "human",
                                            close_reason)
    if rc != 0:
        # tkt-323: fail closed — a refused transition means the ledger is NOT
        # stamped; finish-work must NOT proceed to cleanup/merge.
        raise SystemExit(
            f"finish-ledger: REFUSED — transition refused (rc={rc}); ## Finish "
            f"body written to memory but status NOT flipped + ledger NOT "
            f"appended. Do NOT proceed to cleanup/merge. (tkt-323)"
        )
    rc2 = _ta.commit_transaction(binder, nt, entry)
    if rc2 != 0:
        # tkt-323: fail closed — commit_transaction IO failure leaves no
        # half-stamped ledger; finish-work must NOT proceed.
        raise SystemExit(
            f"finish-ledger: FAILED — commit_transaction rc={rc2} (IO/lock "
            f"failure); atomic stamp FAILED (binder may be unchanged; an orphan ledger entry is possible — investigate the ledger before re-running). Do NOT "
            f"proceed to cleanup/merge. (tkt-323)"
        )
    written = True
    flip_happened = True
elif s != orig:
    # no status flip but ## Finish/prs mutated (e.g. re-stamp, already closed)
    # — write `s` directly (no ledger).
    import tempfile
    d = os.path.dirname(os.path.abspath(binder)) or "."
    mode = os.stat(binder).st_mode
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".finish-ledger.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(s)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, stat.S_IMODE(mode))
        os.replace(tmp, binder)
        written = True
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
print("finish-ledger: stamped" if written else "finish-ledger: no change (idempotent)")
# tkt-360 A1: machine-readable flip signal so the bash staging guard knows a
# ledger entry was appended (vs. a no-flip ## Finish re-stamp, which writes no
# ledger). Grep'd out of human output below alongside `committed:`.
print(f"flip: {1 if flip_happened else 0}")
try:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
finally:
    os.close(lock_fd)
PY
)

# Human output (strip the internal `committed:` and `flip:` lines from
# commit_transaction / the flip signal).
printf '%s\n' "$STAMP_OUT" | grep -vE '^(committed:|flip:)'

# Stage the per-ticket ledger for commit (F2). commit_transaction wrote it.
# Also stage the binder README itself so the caller's single `git commit` captures
# both the ledger and the stamped binder (tkt-317: previously only the JSONL was
# staged, leaving the binder write uncommitted and forcing manual cleanup).
TICKET_ID=$(basename "$(dirname "$BINDER")" | sed -n 's/^\(tkt-[1-9][0-9]*\)-.*/\1/p')
LATTICE_HOME_DIR=$(dirname "$(dirname "$(dirname "$BINDER")")")
LEDGER_FILE="$LATTICE_HOME_DIR/.transition-ledger/${TICKET_ID:-unknown}.jsonl"
# spc-337 A1: stage in the BINDER's repository, not the caller's cwd — a
# finish run from a foreign cwd used to `git add` against the wrong index
# (or no repo at all) and silently drop the ledger (tkt-335).
BINDER_REPO_ROOT=$(git -C "$(dirname "$BINDER")" rev-parse --show-toplevel 2>/dev/null || true)
[[ -f "$LEDGER_FILE" ]] && git -C "${BINDER_REPO_ROOT:-.}" add -- "$LEDGER_FILE" 2>/dev/null || true
# tkt-317: stage the binder README too (previously only the JSONL was staged).
# Surface a staging failure rather than silently masking it — a gitignored
# .lattice (ADR-011 fresh-customer-repo) or a held index lock would otherwise
# leave the binder write uncommitted, re-introducing the dirty-tree bug.
git -C "${BINDER_REPO_ROOT:-.}" add -- "$BINDER" 2>/dev/null || echo "finish-ledger: WARNING — could not stage binder $BINDER (gitignored? index lock?); commit may miss it" >&2

# tkt-360 A1: a status flip appends a ledger entry — assert it actually reached
# the git index. A silent staging drop (gitignored .transition-ledger/, held index
# lock, foreign cwd) is exactly how tkt-356/tkt-357 shipped a flipped binder with
# no ledger commit, turning dev artifacts CI red (transition_ledger_snapshot_mismatch).
# Fail closed with the recovery command — never a silent WARNING.
FLIP_HAPPENED=$(printf '%s\n' "$STAMP_OUT" | sed -n 's/^flip: //p')
if [[ "$FLIP_HAPPENED" == "1" ]]; then
  if [[ -z "$BINDER_REPO_ROOT" ]]; then
    echo "Error: finish-ledger flipped the status but the binder is not in a git repo; cannot assert the ledger $LEDGER_FILE is staged (tkt-360 A1)" >&2
    echo "  recovery: initialize git at the binder root, or run finish-ledger from inside a repo" >&2
    exit 1
  fi
  # Repo-relative ledger path for index comparison (git normalizes to this).
  LEDGER_REL="${LEDGER_FILE#"$BINDER_REPO_ROOT"/}"
  [[ "$LEDGER_REL" == "$LEDGER_FILE" ]] && LEDGER_REL=".lattice/.transition-ledger/${TICKET_ID:-unknown}.jsonl"
  if ! git -C "$BINDER_REPO_ROOT" diff --cached --name-only --full-index 2>/dev/null | grep -Fxq -- "$LEDGER_REL"; then
    echo "Error: finish-ledger flipped the status to closed but the ledger $LEDGER_REL is NOT staged (tkt-360 A1)" >&2
    echo "  the binder status flip MUST land in the same commit as the ledger entry, or dev artifacts CI goes red (transition_ledger_snapshot_mismatch)" >&2
    echo "  common cause: .transition-ledger/ is gitignored, or a held git index lock, or finish-ledger ran from a foreign cwd" >&2
    echo "  recovery: git -C \"$BINDER_REPO_ROOT\" add -- \"$LEDGER_REL\" && re-run finish-ledger, OR commit the staged binder + ledger together" >&2
    exit 1
  fi
fi

exit 0
