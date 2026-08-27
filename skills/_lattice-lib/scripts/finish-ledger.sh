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

PR_N=""
ISSUE_M=""
BINDER=""
REPO=""
MERGED_AT_OVERRIDE=""
CLOSED_AT_OVERRIDE=""
PR_STATE_OVERRIDE=""

usage() {
  cat >&2 <<'EOF'
Usage: finish-ledger.sh --pr <N> [--issue <M>] --binder <path> [--repo <owner/repo>]
                        [--merged-at <ts>] [--closed-at <ts>] [--pr-state MERGED|CLOSED]
  --pr        PR number (required). Fetches mergedAt unless --merged-at given.
  --issue     closing issue number (optional). Fetches closedAt; sets status=closed.
  --binder    path to binder README.md (required).
  --repo      owner/repo for gh (optional; defaults to origin).
  --merged-at override mergedAt (skip gh fetch; tests/offline).
  --closed-at override closedAt (skip gh fetch).
  --pr-state  override PR state MERGED|CLOSED (skip gh fetch).
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
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ -z "$PR_N" ]] && { echo "Error: --pr is required" >&2; usage; }
[[ -z "$BINDER" ]] && { echo "Error: --binder is required" >&2; usage; }

# `gh pr view <arg>` accepts a number, a branch name OR a full URL, and gh's
# flag parser accepts `--repo=owner/name` in positional position. Identifiers
# here are agent-derived (from PR/issue prose), so a pasted URL would stamp
# another repository's mergedAt/closedAt into this repo's binder. Same rule the
# sibling helpers already enforce (cleanup-workspace.sh, update-pr-base.sh,
# alignment-check.sh).
if [[ ! "$PR_N" =~ ^[1-9][0-9]*$ ]]; then
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
#   PR outcome  — hard requirement unless fully overridden
#   issue state — best effort; an unreachable issue records "not closed"
NEED_GH_PR=true
if [[ -n "$PR_STATE_OVERRIDE" ]]; then
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

# --- Resolve closing issue state ---------------------------------------------
CLOSED_AT="$CLOSED_AT_OVERRIDE"
ISSUE_CLOSED=false
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

# --- Stamp the binder (idempotent) --------------------------------------------
python3 - "$BINDER" "$PR_N" "$MERGED_AT" "$CLOSED_AT" "$ISSUE_CLOSED" "$PR_URL" "$ISSUE_M" "$PR_STATE" <<'PY'
import sys, re, os, stat, fcntl

binder, pr_n, merged_at, closed_at, issue_closed, pr_url, issue_m, pr_state = sys.argv[1:9]
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
if merged:
    pr_line = f"- pr-{pr_n} merged: {merged_at}"
else:
    pr_line = f"- pr-{pr_n} closed without merge"
if pr_url:
    pr_line += f" — {pr_url}"
pr_line += " (base merge)" if merged else ""

issue_line = ""
if issue_m and closed_at and issue_closed == "true":
    if pr_url:
        base = pr_url.split("/pull/")[0]  # https://github.com/owner/repo
        issue_line = f"\n- issue #{issue_m} closed: {closed_at} — {base}/issues/{issue_m}"
    else:
        issue_line = f"\n- issue #{issue_m} closed: {closed_at} — https://github.com/<org>/<repo>/issues/{issue_m}"
elif issue_m and not issue_closed == "true":
    issue_line = f"\n- issue #{issue_m}: not closed (closed-without-merge? status recorded without mergedAt claim)"

# 1. Replace `## Finish` body.
# Find the ## Finish section (up to next ## heading or EOF).
m = re.search(r'(^## Finish\s*\n)(.*?)(?=\n## |\Z)', s, flags=re.DOTALL | re.MULTILINE)
if not m:
    # No ## Finish heading — append one.
    s = s.rstrip() + "\n\n## Finish\n\n" + pr_line + issue_line + "\n"
else:
    head, body = m.group(1), m.group(2)
    # Idempotent: if a pr-N line already exists, update mergedAt; else append.
    pr_pat = re.compile(rf'^- pr-{re.escape(pr_n)} (?:merged:|closed without merge).*$', re.MULTILINE)
    if pr_pat.search(body):
        body = pr_pat.sub(pr_line, body)
        # refresh issue line if issue info present
        if issue_line:
            iss_pat = re.compile(rf'^- issue #{re.escape(issue_m)}.*$', re.MULTILINE) if issue_m else None
            if iss_pat and iss_pat.search(body):
                body = iss_pat.sub(issue_line.lstrip("\n"), body)
            else:
                body = body.rstrip() + issue_line + "\n"
    else:
        # Drop a bare "(none yet)" placeholder.
        body = re.sub(r'^- \(none yet\)\s*\n?', '', body, flags=re.MULTILINE)
        body = body.rstrip()
        if body:
            body = body + "\n" + pr_line + issue_line + "\n"
        else:
            body = "\n" + pr_line + issue_line + "\n"
    s = s[:m.start()] + head + body + s[m.end():]

# 2. status: open → closed (only when issue closed or no issue but PR merged).
if issue_closed == "true" or (not issue_m and merged):
    s = re.sub(r'(\| status \|)\s*open\s*(\|)', r'\1 closed \2', s)

# 3. prs table row: record pr-N — URL (idempotent; append for multiple PRs).
# Any `(none…)` placeholder variant — "(none)", "(none yet)", … — is REPLACED,
# never appended beside (digest rev-20260826-172600Z Findings 4: appending
# left "(none) · pr-N …" rows, the tkt-43 duplication class).
prs_entry = f"pr-{pr_n}"
if pr_url:
    prs_entry += f" — {pr_url}"
prs_row = re.compile(r'(\| prs \|)\s*(.*?)\s*(\|)')
m_prs = prs_row.search(s)
if m_prs:
    cur = m_prs.group(2)
    if cur.strip() == "" or re.fullmatch(r'\(none[^)]*\)', cur):
        s = prs_row.sub(lambda mm: f"{mm.group(1)} {prs_entry} {mm.group(3)}", s, count=1)
    elif f"pr-{pr_n}" not in cur:
        s = prs_row.sub(lambda mm: f"{mm.group(1)} {cur} · {prs_entry} {mm.group(3)}", s, count=1)
    else:
        # pr-N already recorded; leave (idempotent)
        pass

if s != orig:
    # Write via temp + atomic rename: a crash (or a second finish session
    # stamping the same binder for a sibling PR) must never leave a truncated
    # binder behind. Preserve the original mode.
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
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
print("finish-ledger: stamped" if s != orig else "finish-ledger: no change (idempotent)")
try:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
finally:
    os.close(lock_fd)
PY

exit 0
