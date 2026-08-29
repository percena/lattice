#!/usr/bin/env bash
# Read-only GitHub↔binder state reconciliation check.
#
# Compares a ticket binder's local state (status / prs / ## Finish ledger)
# with live GitHub issue and referenced-PR state. Detects cross-system drift
# WITHOUT mutating either source. Repository-identity-bound: every gh query
# is pinned to the binder's own repository identity; foreign or unresolved
# targets are rejected so a foreign repo's state can never read as this
# binder's reconciliation.
#
# Drift classes detected (stable reason codes):
#   closed_issue_working_binder   — GH issue CLOSED, binder status working
#   open_issue_closed_binder      — GH issue OPEN, binder status terminal
#   merged_pr_nonterminal_binder   — referenced PR MERGED, binder nonterminal
#   closed_pr_nonterminal_binder   — referenced PR CLOSED, binder nonterminal
#   open_pr_closed_binder          — referenced PR still OPEN, binder closed
#   pr_open_missing_pr             — status pr-open but no PR referenced
#   pr_open_unresolvable_pr        — status pr-open but referenced PR 404
#   merged_pr_missing_finish_ledger — MERGED PR + terminal binder but no Finish
#                                     ledger with a merged: entry
#   repo_identity_mismatch          — binder github/PR URLs point to a
#                                     different repository than the binder origin
#
# Terminal rules follow tkt-150 (finish-ledger terminal cancel) and tkt-151
# (artifact-state invariants): working = queued|in-progress|parked|stuck|
# pr-open|rework|deferred, legacy = open, terminal = closed.
#
# Usage:
#   reconcile-state.sh --binder <path> [--repo <owner/repo>] [--json]
#
# Exit:
#   0 — reconciled (ok:true, no drift)
#   1 — drift detected (ok:false)
#   2 — unknown (gh unavailable / auth / network) or usage / binder invalid
set -euo pipefail

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
bash "$(dirname "${BASH_SOURCE[0]}")/ensure-python3.sh" || exit 1

BINDER=""
REPO=""
AS_JSON=false

usage() {
  cat >&2 <<'EOF'
Usage: reconcile-state.sh --binder <path> [--repo <owner/repo>] [--json]
  --binder  path to ticket binder README.md (required)
  --repo     owner/repo override (must match binder origin if origin resolvable)
  --json     emit deterministic JSON only (default: human summary)
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binder) BINDER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ -z "$BINDER" ]] && { echo "Error: --binder is required" >&2; usage; }
[[ ! -f "$BINDER" ]] && { echo "Error: binder not found: $BINDER" >&2; exit 2; }

# owner/repo becomes a path segment in a gh api URL. Each component must
# contain at least one non-dot character (same rule as finish-ledger.sh).
OWNER_REPO_RE='^[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*$'
if [[ -n "$REPO" && ! "$REPO" =~ $OWNER_REPO_RE ]]; then
  echo "Error: --repo must be owner/name, got: $REPO" >&2
  exit 2
fi

# Binder must be inside a git worktree for origin identity binding.
BINDER_REPO_ROOT=$(git -C "$(dirname "$BINDER")" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$BINDER_REPO_ROOT" ]]; then
  echo "Error: --binder is not inside a git worktree: $BINDER" >&2
  exit 2
fi

BINDER_ORIGIN=$(git -C "$BINDER_REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)

export RS_BINDER="$BINDER"
export RS_REPO="$REPO"
export RS_JSON="$AS_JSON"
export RS_BINDER_ORIGIN="$BINDER_ORIGIN"
export RS_BINDER_ROOT="$BINDER_REPO_ROOT"
# Resolve the sibling lib/ dir using only bash builtins (cd + pwd are
# builtins): the gh-not-installed test runs with a stripped PATH where the
# `dirname` coreutil is absent, and ${BASH_SOURCE[0]%/*} strips the trailing
# filename so the cd lands on the script's own directory. Declared before
# export to avoid masking the substitution's exit code (shellcheck SC2155).
RS_LIB="$(cd "${BASH_SOURCE[0]%/*}" && pwd)/lib"
export RS_LIB

python3 - <<'PY'
import json, os, re, shutil, subprocess, sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, os.environ["RS_LIB"])
import status_vocab

binder_path = os.environ["RS_BINDER"]
repo_arg = os.environ.get("RS_REPO", "")
as_json = os.environ.get("RS_JSON", "false").lower() == "true"
binder_origin = os.environ.get("RS_BINDER_ORIGIN", "")
ticket_name = Path(binder_path).parent.name

# ---------------------------------------------------------------------------
# Repo identity resolution (shared logic with finish-ledger.sh)
# ---------------------------------------------------------------------------
def repo_identity_from_url(raw):
    """Return 'host/owner/repo' (lowercased) or None for a git/https URL.

    Handles git remote origin URLs (https://host/owner/repo.git,
    git@host:owner/repo.git) — exactly two path segments after the host.
    """
    raw = (raw or "").strip()
    if not raw:
        return None
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
        return None
    return f"{host}/{parts[0]}/{parts[1]}".lower()


def repo_identity_from_web_url(url):
    """Return 'host/owner/repo' (lowercased) or None for a GitHub web URL.

    Handles issue/PR/etc web URLs that carry extra path segments beyond
    owner/repo (e.g. https://github.com/owner/repo/issues/7). Takes the
    first two path segments as the repository identity.
    """
    raw = (url or "").strip()
    if not raw:
        return None
    parsed = urlsplit(raw)
    host = parsed.hostname or ""
    if parsed.port:
        host += f":{parsed.port}"
    path = parsed.path.strip("/")
    parts = path.split("/")
    if not host or len(parts) < 2 or not all(parts[:2]):
        return None
    return f"{host}/{parts[0]}/{parts[1]}".lower()


binder_repo_id = repo_identity_from_url(binder_origin)

# --- Determine the target repo for gh queries (bound to binder identity) ---
target_host = None
target_repo = None  # owner/repo
_repo_arg_no_origin = False

if repo_arg:
    if binder_repo_id:
        binder_host = binder_repo_id.split("/")[0]
        candidate_full = f"{binder_host}/{repo_arg}".lower()
        if candidate_full != binder_repo_id:
            print("Error: refusing to reconcile GitHub state from a different "
                  "repository into this binder", file=sys.stderr)
            print(f"  binder repo: {binder_repo_id}", file=sys.stderr)
            print(f"  --repo target: {candidate_full}", file=sys.stderr)
            print("  pass --repo matching the binder origin, or omit --repo "
                  "for auto-resolution", file=sys.stderr)
            sys.exit(2)
        target_host = binder_host
        target_repo = repo_arg
    else:
        # No git origin — identity cannot be verified against origin.
        # tkt-179 A9: fall back to the github URL repo identity if available;
        # if neither is available, refuse rather than accept --repo unchallenged.
        # (github_url_repo_id is parsed later from the binder, so we set a
        # flag and re-check after binder parsing.)
        target_host = "github.com"
        target_repo = repo_arg
        _repo_arg_no_origin = True
elif binder_repo_id:
    parts = binder_repo_id.split("/", 1)
    target_host = parts[0]
    target_repo = parts[1]
# else: try to resolve from the binder's github URL (parsed below)

# ---------------------------------------------------------------------------
# Binder parsing
# ---------------------------------------------------------------------------
text = Path(binder_path).read_text(encoding="utf-8", errors="replace")

def first_table_block(text):
    """Return the first contiguous Markdown table block (binder card)."""
    lines, in_table = [], False
    for line in text.splitlines():
        if line.startswith("|"):
            in_table = True
            lines.append(line)
        elif in_table:
            break
    return "\n".join(lines)

table = first_table_block(text)

def table_field(name):
    m = re.search(rf"^\|\s*{re.escape(name)}\s*\|\s*([^|]+?)\s*\|",
                  table, re.I | re.M)
    return m.group(1).strip() if m else ""

status = table_field("status").strip().lower()
github_url = table_field("github").strip()
prs_raw = table_field("prs").strip()

# Parse issue number + repo identity from the github URL
issue_number = None
github_url_repo_id = None
if github_url and github_url.lower() not in ("(none)", "(none yet)"):
    github_url_repo_id = repo_identity_from_web_url(github_url)
    m = re.search(r"/issues/(\d+)", github_url)
    if m:
        issue_number = int(m.group(1))

# Fall back to the binder directory name (tkt-N-*)
if issue_number is None:
    m = re.match(r"tkt-(\d+)-", ticket_name)
    if m:
        issue_number = int(m.group(1))

# If no origin identity, try the github URL repo identity (best effort)
if not target_repo and github_url_repo_id:
    target_host = github_url_repo_id.split("/")[0]
    target_repo = "/".join(github_url_repo_id.split("/")[1:])
    binder_repo_id = github_url_repo_id  # adopt for mismatch checks

# tkt-179 A9: --repo passed but no git origin. If the binder has a github URL,
# use its repo identity as the fallback and verify --repo matches it.
if _repo_arg_no_origin:
    if github_url_repo_id:
        candidate_full = f"{github_url_repo_id.split('/')[0]}/{repo_arg}".lower()
        if candidate_full != github_url_repo_id:
            print("Error: refusing to reconcile GitHub state from a different "
                  "repository into this binder", file=sys.stderr)
            print(f"  binder github URL repo: {github_url_repo_id}", file=sys.stderr)
            print(f"  --repo target: {candidate_full}", file=sys.stderr)
            print("  pass --repo matching the binder github URL, or omit --repo "
                  "for auto-resolution", file=sys.stderr)
            sys.exit(2)
        binder_repo_id = github_url_repo_id
        target_host = github_url_repo_id.split("/")[0]
        target_repo = "/".join(github_url_repo_id.split("/")[1:])
    else:
        # No identity available at all — refuse rather than accept --repo unchallenged
        print("Error: --repo provided but no binder repo identity available "
              "(no git origin and no github URL); cannot verify --repo identity",
              file=sys.stderr)
        sys.exit(2)

# Parse PR entries from the prs row (tkt-74 canon: pr-N — <URL>)
PRS_ENTRY_RE = re.compile(r"pr-([1-9][0-9]*)\s+—\s+(https?://[^\s,]+)")
prs_entries = []
for m in PRS_ENTRY_RE.finditer(prs_raw):
    pr_n = int(m.group(1))
    pr_url = m.group(2)
    pr_repo_id = repo_identity_from_web_url(pr_url)
    prs_entries.append({
        "number": pr_n,
        "url": pr_url,
        "repo_id": pr_repo_id,
    })

# ---------------------------------------------------------------------------
# Finish ledger detection (tkt-151 terminal rules, shared with the validator)
# ---------------------------------------------------------------------------
FINISH_SECTION_RE = re.compile(
    r"^##\s+Finish\b.*?\n(.*?)(?=^##\s|\Z)", re.S | re.M)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
PRS_PLACEHOLDER_RE = re.compile(r"^\(none.*\)$", re.I)


def has_finish_ledger(text):
    m = FINISH_SECTION_RE.search(text)
    if not m:
        return False
    body = HTML_COMMENT_RE.sub("", m.group(1))
    for line in body.splitlines():
        content = line.strip().lstrip("-").strip()
        if content and PRS_PLACEHOLDER_RE.fullmatch(content) is None:
            return True
    return False


def finish_ledger_merged(text):
    m = FINISH_SECTION_RE.search(text)
    if not m:
        return False
    body = HTML_COMMENT_RE.sub("", m.group(1))
    return re.search(r"\bmerged:\s", body) is not None


# ---------------------------------------------------------------------------
# Terminal rules (tkt-150 / tkt-151). Vocabulary single-sourced in
# lib/status_vocab.py (tkt-189 / spc-186 A2): working = queued|in-progress|
# parked|stuck|pr-open|rework|deferred, legacy = open, terminal = closed.
# ---------------------------------------------------------------------------
STATUS_WORKING = status_vocab.STATUS_WORKING
STATUS_TERMINAL = status_vocab.STATUS_TERMINAL
STATUS_LEGACY = status_vocab.STATUS_LEGACY


def is_terminal(s):
    return s in STATUS_TERMINAL


def is_nonterminal(s):
    return s in STATUS_WORKING or s in STATUS_LEGACY


# ---------------------------------------------------------------------------
# Repo identity mismatch checks
# ---------------------------------------------------------------------------
repo_mismatches = []

if github_url_repo_id and binder_repo_id and github_url_repo_id != binder_repo_id:
    repo_mismatches.append({
        "code": "repo_identity_mismatch",
        "detail": (f"binder github URL is {github_url_repo_id} "
                   f"but binder origin is {binder_repo_id}"),
        "ids": [github_url],
    })

foreign_prs = []
for pr in prs_entries:
    pr_repo = pr["repo_id"]
    if pr_repo and binder_repo_id and pr_repo != binder_repo_id:
        repo_mismatches.append({
            "code": "repo_identity_mismatch",
            "detail": (f"pr-{pr['number']} URL is {pr_repo} "
                       f"but binder origin is {binder_repo_id}"),
            "ids": [f"pr-{pr['number']}"],
        })
        foreign_prs.append(pr["number"])

# ---------------------------------------------------------------------------
# Cannot resolve repository identity → unknown (never a false clean result)
# ---------------------------------------------------------------------------
if not target_repo:
    result = {
        "ok": False,
        "result": "unknown",
        "binder": binder_path,
        "ticket": ticket_name,
        "error": ("cannot resolve repository identity for this binder "
                  "(no git origin, no --repo, no github URL)"),
        "drifts": [],
        "read_only": True,
    }
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        print(f"# reconcile-state · {ticket_name}")
        print()
        print("## UNKNOWN")
        print(f"- {result['error']}")
        print()
        print("## summary: result=unknown")
    sys.exit(2)

target_full = f"{target_host}/{target_repo}" if target_host else target_repo

# ---------------------------------------------------------------------------
# gh availability + auth
# ---------------------------------------------------------------------------
gh_bin = shutil.which("gh")
if not gh_bin:
    result = {
        "ok": False,
        "result": "unknown",
        "binder": binder_path,
        "ticket": ticket_name,
        "repo": target_full,
        "error": "gh CLI not installed or not on PATH",
        "drifts": repo_mismatches,
        "read_only": True,
    }
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        print(f"# reconcile-state · {ticket_name}")
        print(f"binder:   {binder_path}")
        print(f"repo:     {target_full}")
        print()
        print("## UNKNOWN")
        print(f"- {result['error']}")
        print()
        print("## summary: result=unknown")
    sys.exit(2)


def gh_auth_ok():
    try:
        r = subprocess.run([gh_bin, "auth", "status"],
                           capture_output=True, text=True, timeout=15)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


auth_ok = gh_auth_ok()


def gh_query(kind, number):
    """Return (data_dict_or_None, error_kind).

    error_kind: None (ok) | 'not_found' | 'unknown'
    """
    try:
        cmd = [gh_bin, kind, "view", str(number),
               "--repo", target_full,
               "--json", "state,closedAt,mergedAt,url"]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and r.stdout.strip():
            return json.loads(r.stdout), None
        stderr = r.stderr.lower()
        if "not found" in stderr or "could not resolve" in stderr:
            return None, "not_found"
        return None, "unknown"
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        return None, "unknown"


# ---------------------------------------------------------------------------
# Query GitHub state
# ---------------------------------------------------------------------------
issue_data = None
issue_error = None
if issue_number:
    if auth_ok:
        issue_data, issue_error = gh_query("issue", issue_number)
    else:
        issue_error = "unknown"

pr_results = []
for pr in prs_entries:
    if pr["number"] in foreign_prs:
        pr_results.append({
            "number": pr["number"], "url": pr["url"],
            "data": None, "error": "foreign_repo",
        })
        continue
    if auth_ok:
        data, error = gh_query("pr", pr["number"])
    else:
        data, error = None, "unknown"
    pr_results.append({
        "number": pr["number"], "url": pr["url"],
        "data": data, "error": error,
    })

# ---------------------------------------------------------------------------
# Unknown state (auth / network) — never a false clean result
# ---------------------------------------------------------------------------
unknown_errors = []
if not auth_ok:
    unknown_errors.append(
        "gh auth status failed (not authenticated or network unreachable)")
if issue_error == "unknown":
    unknown_errors.append(
        f"gh issue view {issue_number} failed with auth/network error")
for pr_r in pr_results:
    if pr_r["error"] == "unknown":
        unknown_errors.append(
            f"gh pr view {pr_r['number']} failed with auth/network error")

if unknown_errors:
    result = {
        "ok": False,
        "result": "unknown",
        "binder": binder_path,
        "ticket": ticket_name,
        "repo": target_full,
        "status": status,
        "issue": {
            "number": issue_number,
            "state": issue_data.get("state") if issue_data else None,
            "error": issue_error if issue_error != "unknown" else "unknown",
        },
        "prs": [{
            "number": p["number"],
            "state": p["data"].get("state") if p["data"] else None,
            "error": p["error"],
        } for p in pr_results],
        "errors": unknown_errors,
        "drifts": repo_mismatches,
        "read_only": True,
    }
    if as_json:
        print(json.dumps(result, indent=2))
    else:
        print(f"# reconcile-state · {ticket_name}")
        print(f"binder:   {binder_path}")
        print(f"repo:     {target_full}")
        print(f"status:   {status or '(none)'}")
        print()
        print("## UNKNOWN")
        for e in unknown_errors:
            print(f"- {e}")
        if repo_mismatches:
            print()
            print("## DRIFT (repo identity)")
            for d in repo_mismatches:
                print(f"- [{d['code']}] {d['detail']}")
        print()
        print("## summary: result=unknown")
    sys.exit(2)

# ---------------------------------------------------------------------------
# Drift detection
# ---------------------------------------------------------------------------
drifts = list(repo_mismatches)

issue_state = issue_data.get("state") if issue_data else None
issue_closed = issue_state == "CLOSED"

# 1. closed issue vs working binder
if issue_closed and is_nonterminal(status):
    drifts.append({
        "code": "closed_issue_working_binder",
        "detail": (f"issue #{issue_number} is CLOSED but binder status "
                   f"is '{status}' (working)"),
        "ids": [f"#{issue_number}", status],
    })

# 1b. open issue vs closed binder (reverse drift — tkt-179 A7)
if issue_data and not issue_closed and is_terminal(status):
    drifts.append({
        "code": "open_issue_closed_binder",
        "detail": (f"issue #{issue_number} is OPEN but binder status is "
                   f"'{status}' (terminal); a closed binder requires a "
                   f"closed issue"),
        "ids": [f"#{issue_number}", status],
    })

# 2-4. PR state vs binder status
for pr_r in pr_results:
    pr_n = pr_r["number"]
    if pr_r["error"] == "foreign_repo":
        continue  # already reported as repo_identity_mismatch
    if not pr_r["data"]:
        if pr_r["error"] == "not_found" and status == "pr-open":
            drifts.append({
                "code": "pr_open_unresolvable_pr",
                "detail": (f"binder status is pr-open but pr-{pr_n} "
                           f"could not be resolved on GitHub (not found)"),
                "ids": [f"pr-{pr_n}"],
            })
        continue
    pr_state = pr_r["data"].get("state")
    if pr_state == "MERGED" and is_nonterminal(status):
        drifts.append({
            "code": "merged_pr_nonterminal_binder",
            "detail": (f"pr-{pr_n} is MERGED but binder status is "
                       f"'{status}' (nonterminal)"),
            "ids": [f"pr-{pr_n}", status],
        })
    elif pr_state == "CLOSED" and is_nonterminal(status):
        drifts.append({
            "code": "closed_pr_nonterminal_binder",
            "detail": (f"pr-{pr_n} is CLOSED (without merge) but binder "
                       f"status is '{status}' (nonterminal)"),
            "ids": [f"pr-{pr_n}", status],
        })
    elif pr_state == "OPEN" and is_terminal(status):
        drifts.append({
            "code": "open_pr_closed_binder",
            "detail": (f"pr-{pr_n} is still OPEN but binder status "
                       f"is 'closed'"),
            "ids": [f"pr-{pr_n}"],
        })

# 5. pr-open with no referenced PR
if status == "pr-open" and not prs_entries:
    drifts.append({
        "code": "pr_open_missing_pr",
        "detail": ("binder status is pr-open but no PRs are referenced "
                   "in the prs field"),
        "ids": [status],
    })

# 6. MERGED PR + terminal binder but no Finish ledger with merged: entry
#    (tkt-179 A8): has_finish_ledger and finish_ledger_merged are used here
#    in drift detection — a binder with status: closed, a MERGED PR, and no
#    Finish ledger with a merged: entry is flagged as drift.
if is_terminal(status) and any(
        pr_r.get("data") and pr_r["data"].get("state") == "MERGED"
        for pr_r in pr_results
        if pr_r.get("error") != "foreign_repo"
):
    if not has_finish_ledger(text) or not finish_ledger_merged(text):
        drifts.append({
            "code": "merged_pr_missing_finish_ledger",
            "detail": ("binder has a MERGED PR and terminal status but no "
                       "Finish ledger with a merged: entry — interrupted "
                       "finish-work?"),
            "ids": [],
        })
# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
ok = len(drifts) == 0
result = {
    "ok": ok,
    "result": "ok" if ok else "drift",
    "binder": binder_path,
    "ticket": ticket_name,
    "repo": target_full,
    "binder_repo_id": binder_repo_id,
    "status": status,
    "issue": {
        "number": issue_number,
        "state": issue_state,
        "url": issue_data.get("url") if issue_data else None,
    },
    "prs": [{
        "number": p["number"],
        "state": p["data"].get("state") if p["data"] else None,
        "url": p["url"],
        "error": p["error"],
    } for p in pr_results],
    "finish_ledger": {
        "has_ledger": has_finish_ledger(text),
        "merged": finish_ledger_merged(text),
    },
    "drifts": drifts,
    "read_only": True,
}

if as_json:
    print(json.dumps(result, indent=2))
else:
    print(f"# reconcile-state · {ticket_name}")
    print(f"binder:   {binder_path}")
    print(f"repo:     {target_full}")
    print(f"status:   {status or '(none)'}")
    if issue_number:
        iss = issue_state or "(unresolved)"
        print(f"issue:    #{issue_number} {iss}")
    else:
        print("issue:    (no issue number resolved)")
    if pr_results:
        parts = []
        for p in pr_results:
            st = p["data"].get("state") if p["data"] else (p["error"] or "unresolved")
            parts.append(f"pr-{p['number']} ({st})")
        print(f"prs:      {', '.join(parts)}")
    else:
        print("prs:      (none)")
    print()
    if drifts:
        print("## DRIFT")
        for d in drifts:
            print(f"- [{d['code']}] {d['detail']}")
        print()
        print("## repair hint")
        print("- This check is read-only: update binder status / prs / Finish "
              "ledger to match GitHub state, or update GitHub (close issue / "
              "merge PR) to match binder intent.")
        print("- Re-run: reconcile-state.sh --binder <path>  "
              "(then finish-work when reconciled)")
        print("- See docs/morning-triage.md (monorepo, when present) for the manual recovery route.")
        print()
        print(f"## summary: ok=false drifts={len(drifts)}")
        print("reconcile: drift detected — manual recovery needed")
    else:
        print("## summary: ok=true drifts=0")
        print("reconcile: no drift detected")

sys.exit(0 if ok else 1)
PY
