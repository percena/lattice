#!/usr/bin/env bash
# Stamp a ticket binder + its GitHub issue right after `gh pr create` — one call.
# Called by create-pr AFTER a NEW PR opens, from the feature worktree.
#
#   binder: field-table `prs` row → canonical `pr-N — <URL>`; `status` → pr-open
#   issue:  mirror the binder's checked `- [x]` acceptance items into the issue
#           body's Acceptance checkboxes (`gh issue edit --body-file`) — ONLY for
#           Lattice-template issues. Adopted binders (`adopted: true`) mark the
#           issue body hand-created/append-only: post ONE comment instead.
#
# ORDER MATTERS: check binder acceptance boxes, then stamp — the issue sync
# mirrors only checked boxes. `--check-all` checks every unchecked binder box
# first (refused when the Acceptance section carries a deferral note).
#
# Mirroring is by A*-id match (`**A1**` in the binder item ↔ `A1` in the issue
# line); items without ids fall back to ordinal position within the Acceptance
# section. One-directional: boxes are only checked, never unchecked.
#
# Idempotent: re-running for the same PR changes nothing (binder rows already
# canonical, issue boxes already checked, comment deduped by hidden marker).
# No-op + note when the binder is missing (ticket-only flow) — does NOT fail.
#
# Usage:
#   stamp-pr-open.sh --pr <N> [--issue <M>] [--binder <path>] [--repo <owner/repo>]
#                    [--check-all] [--dry-run]
#   Exits 0 on success or no-binder-skip; 1 on gh/IO failure; 2 on usage.
set -euo pipefail

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
bash "$(dirname "${BASH_SOURCE[0]}")/ensure-python3.sh" || exit 1

PR_N=""
ISSUE_M=""
BINDER=""
REPO=""
DRY_RUN=false
CHECK_ALL=false
FORCE_SIDE_STATE=false
SIDE_STATE_REASON=""

usage() {
  cat >&2 <<'EOF'
Usage: stamp-pr-open.sh --pr <N> [--issue <M>] [--binder <path>] [--repo <owner/repo>]
                        [--check-all] [--force-side-state --reason "<text>"] [--dry-run]

Order matters: check binder acceptance boxes, then stamp — the issue sync
mirrors only checked boxes (unchecked binder boxes sync nothing).

  --pr        PR number (required). URL + state resolved via gh.
  --issue     issue number (optional; default: parsed from the binder's github row).
  --binder    path to binder README.md (optional; default: located from the
              current branch's tkt-<id>- worktree bind).
  --repo      owner/repo for gh (optional; defaults to origin).
  --check-all check ALL unchecked binder acceptance boxes, then mirror.
              REFUSED when the Acceptance section carries a deferral note
              (a line containing "defer") — deferred items force explicit
              per-box checking.
  --force-side-state  override the side-state guard. A binder parked/stuck/
              rework/deferred holds an external signal that a pr-open stamp
              would silently lose; the guard REFUSES the flip without this
              flag. The override requires --reason and writes a structured
              trace to the binder ## Decision journal (operator-adjudicated
              per ADR-007 sec.5b; no default break-glass).
  --reason    rationale for --force-side-state (required with that flag).
  --dry-run   report what would change; mutate nothing (binder or GitHub).
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR_N="${2:-}"; shift 2 ;;
    --issue) ISSUE_M="${2:-}"; shift 2 ;;
    --binder) BINDER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --check-all) CHECK_ALL=true; shift ;;
    --force-side-state) FORCE_SIDE_STATE=true; shift ;;
    --reason) SIDE_STATE_REASON="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ -z "$PR_N" ]] && { echo "Error: --pr is required" >&2; usage; }
if [[ "$FORCE_SIDE_STATE" == true && -z "$SIDE_STATE_REASON" ]]; then
  echo "Error: --force-side-state requires --reason \"<operator-adjudicated rationale>\"" >&2
  usage
fi

# Same identifier hygiene as finish-ledger.sh: `gh pr view` accepts URLs and
# branch names, and gh's parser accepts `--repo=owner/name` positionally, so a
# pasted URL would stamp another repository's PR into this binder.
if [[ ! "$PR_N" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --pr must be a positive GitHub PR number, got: $PR_N" >&2
  exit 2
fi
if [[ -n "$ISSUE_M" && ! "$ISSUE_M" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --issue must be a positive GitHub issue number, got: $ISSUE_M" >&2
  exit 2
fi
OWNER_REPO_RE='^[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*$'
if [[ -n "$REPO" && ! "$REPO" =~ $OWNER_REPO_RE ]]; then
  echo "Error: --repo must be owner/name, got: $REPO" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh not found on PATH (stamp-pr-open resolves the PR URL via gh)" >&2
  exit 1
fi

# --- Locate the binder --------------------------------------------------------
if [[ -z "$BINDER" ]]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  BRANCH=$(git branch --show-current 2>/dev/null || true)
  if [[ -z "$ROOT" || ! "$BRANCH" =~ ^tkt-[1-9][0-9]*- ]]; then
    echo "stamp-pr-open: no --binder and branch '${BRANCH:-?}' is not a tkt-<id>- bind — skip (ticket-only flow)"
    exit 0
  fi
  BINDER="$ROOT/.lattice/tickets/$BRANCH/README.md"
fi

if [[ ! -f "$BINDER" ]]; then
  echo "stamp-pr-open: no binder at $BINDER — skip (ticket-only flow)"
  exit 0
fi

# --- Binder path containment (same law as finish-ledger.sh) -------------------
# This script rewrites $BINDER. The path is agent-derived; a cloned repo can
# ship a binder path as a symlink to anything. Resolve, refuse symlinked
# components, require a regular file under the repo's .lattice/ tree.
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

# --- --check-all guard: deferral notes force explicit per-box checking --------
# Runs BEFORE any mutation (binder or GitHub). A deferral note in the
# Acceptance section means some boxes are deliberately open; blanket-checking
# would erase that intent, so refuse and make the caller check per box.
if $CHECK_ALL; then
  DEFER_LINES=$(python3 - "$BINDER" <<'PY'
import re, sys

s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^#{2,4} Acceptance\b.*?\n(.*?)(?=\n#{1,4} |\Z)', s, re.DOTALL | re.MULTILINE)
if m:
    for line in m.group(1).splitlines():
        if re.search(r'defer', line, re.IGNORECASE):
            print(line.strip())
PY
)
  if [[ -n "$DEFER_LINES" ]]; then
    echo "Error: --check-all refused — the binder Acceptance section contains deferral note(s):" >&2
    printf '%s\n' "$DEFER_LINES" | sed 's/^/  /' >&2
    echo "  deferred items must stay unchecked; check the delivered boxes explicitly, then re-run without --check-all" >&2
    exit 1
  fi
fi

# --- Repo identity binding (refuse-foreign-repo, as finish-ledger.sh) ---------
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

BINDER_ORIGIN=$(git -C "$BINDER_REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)
BINDER_REPO_ID=$(repo_identity_from_url "$BINDER_ORIGIN" 2>/dev/null || true)

GH_ARGS=()
if [[ -n "$REPO" && -n "$BINDER_REPO_ID" ]]; then
  BINDER_HOST=${BINDER_REPO_ID%%/*}
  TARGET_HOST=${GH_HOST:-$BINDER_HOST}
  GH_TARGET_REPO_ID=$(printf '%s/%s' "$TARGET_HOST" "$REPO" | tr '[:upper:]' '[:lower:]')
  # Pin the same host in the actual gh queries (see finish-ledger.sh).
  GH_ARGS=(--repo "$TARGET_HOST/$REPO")
else
  [[ -n "$REPO" ]] && GH_ARGS=(--repo "$REPO")
  GH_TARGET_URL=$(gh repo view --json url -q '.url' 2>/dev/null || true)
  GH_TARGET_REPO_ID=$(repo_identity_from_url "$GH_TARGET_URL" 2>/dev/null || true)
fi
if [[ -n "$GH_TARGET_REPO_ID" && -n "$BINDER_REPO_ID" && "$BINDER_REPO_ID" != "$GH_TARGET_REPO_ID" ]]; then
  echo "Error: refusing to stamp GitHub state from a different repository into this binder" >&2
  echo "  binder repo: $BINDER_REPO_ID" >&2
  echo "  gh target:   $GH_TARGET_REPO_ID" >&2
  exit 1
fi
if [[ -z "$GH_TARGET_REPO_ID" || -z "$BINDER_REPO_ID" ]]; then
  echo "Error: cannot bind PR #$PR_N to this binder's repository" >&2
  echo "  the binder's repo and the gh target must both be known and identical" >&2
  echo "  binder repo: ${BINDER_REPO_ID:-(unresolved origin)} at $BINDER_REPO_ROOT" >&2
  echo "  gh target:   ${GH_TARGET_REPO_ID:-(unknown)}" >&2
  exit 1
fi

# --- Resolve the PR (must be OPEN: this stamp records an opened PR) -----------
PR_JSON=$(gh pr view "$PR_N" ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json url,state 2>/dev/null || true)
if [[ -z "$PR_JSON" ]]; then
  echo "Error: could not read PR #$PR_N (gh auth? wrong repo?)" >&2
  exit 1
fi
eval "$(printf '%s' "$PR_JSON" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
def emit(name, value):
    normalized = "" if value is None else str(value)
    print(f"{name}={shlex.quote(normalized)}")
emit("GH_PR_URL", d.get("url") or "")
emit("GH_PR_STATE", d.get("state") or "")
')"
PR_URL="$GH_PR_URL"
if [[ -z "$PR_URL" ]]; then
  echo "Error: PR #$PR_N has no URL in gh output" >&2
  exit 1
fi
if [[ "$GH_PR_STATE" != "OPEN" ]]; then
  # Symmetric with finish-ledger's OPEN refusal: pr-open records an opened PR;
  # merged/closed outcomes belong to finish-ledger.sh.
  echo "Error: PR #$PR_N is $GH_PR_STATE, not OPEN — use finish-ledger.sh for outcomes" >&2
  exit 1
fi

# --- Issue number: --issue wins; else the binder's github row -----------------
if [[ -z "$ISSUE_M" ]]; then
  ISSUE_M=$(grep -E '^\| *github *\|' "$BINDER" | head -1 \
    | grep -oE '/issues/[1-9][0-9]*' | head -1 | grep -oE '[1-9][0-9]*' || true)
fi

ADOPTED=false
if grep -qE '^\| *adopted *\| *true *\|' "$BINDER"; then
  ADOPTED=true
fi

# --- Stamp the binder (locked + atomic, finish-ledger conventions) ------------
STAMP_MODE=$($DRY_RUN && echo "dry-run" || echo "write")
CHECK_ALL_MODE=$($CHECK_ALL && echo "check-all" || echo "keep-boxes")
FORCE_MODE=$($FORCE_SIDE_STATE && echo "force" || echo "guard")
BINDER_ROWS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
STAMP_OUT=$(BINDER_ROWS_LIB="$BINDER_ROWS_LIB" python3 - "$BINDER" "$PR_N" "$PR_URL" "$STAMP_MODE" "$CHECK_ALL_MODE" "$FORCE_MODE" "$SIDE_STATE_REASON" <<'PY'
import datetime, sys, re, os, stat, fcntl, importlib.util

sys.path.insert(0, os.environ["BINDER_ROWS_LIB"])
import binder_rows
import status_vocab
# spc-297: import transition-api for in-lock single-write atomicity.
_ta_path = os.path.join(os.environ["BINDER_ROWS_LIB"], "..", "transition-api.py")
_ta_spec = importlib.util.spec_from_file_location("transition_api", _ta_path)
_ta = importlib.util.module_from_spec(_ta_spec); _ta_spec.loader.exec_module(_ta)

binder, pr_n, pr_url, mode, box_mode, force_mode, side_reason = sys.argv[1:8]
dry_run = mode == "dry-run"
check_all = box_mode == "check-all"
force_side_state = force_mode == "force"

# Exclusive lock on the containing directory for the whole read-modify-write
# (stable inode across atomic replaces; no untracked lock artifact).
lock_dir = os.path.dirname(os.path.abspath(binder)) or "."
lock_fd = os.open(lock_dir, os.O_RDONLY)
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
except OSError as exc:
    os.close(lock_fd)
    raise SystemExit(f"stamp-pr-open: cannot lock binder directory: {exc}")

s = open(binder, encoding="utf-8").read()
orig = s

# prs row: canonical `pr-N — URL`, comma-joined for multi-PR tickets
# (grammar single-sourced in lib/binder_rows.py — tkt-91; placeholder
# variants are REPLACED, never appended beside — digest rev-20260826-172600Z
# Findings 4; the legacy ` · ` joiner is never emitted).
prs_row = re.compile(r'(\| prs \|)\s*(.*?)\s*(\|)')
m_prs = prs_row.search(s)
if m_prs:
    if not pr_url:
        print("stamp-pr-open: WARNING — no PR URL resolved; prs row left untouched (bare pr-N is off-canon)", file=sys.stderr)
    else:
        merged = binder_rows.merge_row(m_prs.group(2), pr_n, pr_url)
        s = prs_row.sub(lambda mm: f"{mm.group(1)} {merged} {mm.group(3)}", s, count=1)
else:
    print("stamp-pr-open: WARNING — binder has no `| prs |` row; not stamped", file=sys.stderr)

# --check-all: check every unchecked box in the Acceptance section. The
# deferral guard already refused before this point when a deferral note exists.
boxes_checked = 0
if check_all:
    m_acc = re.search(r'^#{2,4} Acceptance\b.*?\n(.*?)(?=\n#{1,4} |\Z)', s, re.DOTALL | re.MULTILINE)
    if m_acc:
        section = m_acc.group(1)
        new_section, boxes_checked = re.subn(
            r'^(\s*- \[) (\] )', r'\1x\2', section, flags=re.MULTILINE)
        if boxes_checked:
            s = s[:m_acc.start(1)] + new_section + s[m_acc.end(1):]
    else:
        print("stamp-pr-open: --check-all — binder has no Acceptance section; nothing to check", file=sys.stderr)

# --- status row → pr-open with the side-state guard (tkt-189 / spc-186 A2) --
# Vocabulary + policy single-sourced in lib/status_vocab.py. Never regress a
# closed ticket (finish-ledger owns the terminal stamp). Side states
# (parked/stuck/rework/deferred) hold an external signal a pr-open stamp
# would silently lose: REFUSE without --force-side-state --reason, which
# journals a structured operator-adjudicated trace (ADR-007 sec.5b; no
# default break-glass). tkt-237 M3: deferred was missing from the guard
# (hit the else branch → silent flip); now guarded like the rest. queued →
# pr-open is a direct jump: allowed but WARN-journaled so the "started"
# signal is logged, not silently lost (in-progress → pr-open stays the
# default, ungated, no trace).
#
# A1.3 (spc-270): the status flip + updated bump + the structured journal
# trace are NO LONGER written here. The python only mutates non-status
# fields (prs row, acceptance boxes) and refuses side-state crossings
# without --force-side-state (so the binder stays untouched on refusal).
# It emits @@TRANSITION_FROM:<prior>|<reason>|<owner>@@ plus, when a trace
# applies, @@JOURNAL_B64:<base64>@@; bash routes the flip through
# `transition-api.py commit --append-journal` so journal + status +
# updated + ledger land in ONE atomic transaction (a crash before commit
# leaves no trace → re-run appends it once, no duplicate).
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
status_row = re.compile(r'(\| status \|)\s*(.*?)\s*(\|)')
m_status = status_row.search(s)
prior = m_status.group(2).strip() if m_status else ""
status_trace = ""  # journal entry text; emitted for bash → commit --append-journal
transition_reason = "create-pr opens the PR"  # default; overridden per branch
transition_owner = "agent"
if prior == "closed":
    print("stamp-pr-open: binder status is closed — left untouched")
elif status_vocab.is_side_state(prior):
    if not force_side_state:
        print(
            f"stamp-pr-open: REFUSED — binder status is `{prior}` (side state). "
            f"A pr-open stamp would silently lose the {prior} signal "
            f"(parked=decision pending / stuck=needs investigation / "
            f"rework=PR returned / deferred=spec-superseded|blocked-by-failure|"
            f"fuse-halt). To override: --force-side-state "
            f"--reason \"<operator-adjudicated rationale>\"",
            file=sys.stderr,
        )
        raise SystemExit(1)
    status_trace = (
        f"- {stamp} — side-state override: {prior} → pr-open "
        f"(reason: {side_reason}; PR #{pr_n}) "
        f"[operator-adjudicated — ADR-007 sec.5b]"
    )
    transition_reason = "force-side-state override (operator-adjudicated)"
    transition_owner = "human"
    print(f"stamp-pr-open: side-state override traced ({prior} → pr-open)")
elif prior in status_vocab.DIRECT_JUMP_SOURCES:
    status_trace = (
        f"- {stamp} — direct jump: {prior} → pr-open "
        f"(in-progress stamp skipped; PR #{pr_n}) "
        f"[WARN — signal logged, not silently lost]"
    )
    transition_reason = "direct jump (in-progress skipped)"
    transition_owner = "agent"
    print(f"stamp-pr-open: WARN — direct jump {prior} → pr-open journaled", file=sys.stderr)
else:
    pass  # in-progress → pr-open: ungated default, no trace; commit flips status

# Bump `updated` atomically with the status stamp (spc-186 A4 / tkt-191).
# spc-297: single-write atomicity. The status flip + journal trace + `updated`
# + ledger land in ONE `commit_transaction` (merged with the prs/acceptance
# mutations already in `s`), called inside this dir lock. A crash leaves
# neither a half-mutated binder nor a misleading ledger (A1.2 fail-close,
# in-process). No `record`/direct-stamp bypass; no two-write window.
TICKET_ID = ""
m_tid = re.match(r'^(tkt-[1-9][0-9]*)', os.path.basename(os.path.dirname(binder)))
if m_tid:
    TICKET_ID = m_tid.group(1)
flip = bool(prior) and prior not in ("closed", "pr-open")
written = False
if dry_run:
    pass  # no write; DRY-RUN message below
elif flip:
    rc, nt, entry = _ta.prepare_commit_text(
        s, TICKET_ID, "pr-open", transition_owner, transition_reason,
        force_reason=(side_reason if force_side_state else None),
        journal_entry=(status_trace or None))
    if rc != 0:
        # tkt-323: fail closed — a refused transition leaves the binder
        # untouched (status NOT pr-open); create-pr/finish must NOT proceed.
        raise SystemExit(
            f"stamp-pr-open: REFUSED — transition refused (rc={rc}); binder "
            f"NOT flipped to pr-open + ledger NOT appended. Do NOT proceed "
            f"to create-pr/finish. (tkt-323)"
        )
    rc2 = _ta.commit_transaction(binder, nt, entry)
    if rc2 != 0:
        # tkt-323: fail closed — commit_transaction IO failure leaves no
        # half-flipped binder; create-pr/finish must NOT proceed.
        raise SystemExit(
            f"stamp-pr-open: FAILED — commit_transaction rc={rc2} (IO/lock "
            f"failure); atomic stamp FAILED (binder may be unchanged; an orphan ledger entry is possible — investigate the ledger before re-running). Do NOT "
            f"proceed to create-pr/finish. (tkt-323)"
        )
    written = True
elif s != orig:
    # no status flip but prs/acceptance mutated (multi-PR append, or acceptance
    # boxes on an already-pr-open binder) — write `s` directly (no ledger;
    # pr-open→pr-open is not a recorded rebase-void).
    import tempfile
    d = os.path.dirname(os.path.abspath(binder)) or "."
    fmode = os.stat(binder).st_mode
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".stamp-pr-open.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(s)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, stat.S_IMODE(fmode))
        os.replace(tmp, binder)
        written = True
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise

box_note = f" + {boxes_checked} acceptance box(es) checked" if boxes_checked else ""
trace_note = " + side-state override traced" if status_trace and status_trace.startswith("- ") and "override" in status_trace else (" + direct-jump WARN journaled" if status_trace else "")
stamp_label = binder_rows.format_entry(pr_n, pr_url) if pr_url else f"pr-{pr_n} (URL unresolved)"
if dry_run and (flip or s != orig):
    print(f"stamp-pr-open: DRY-RUN — would stamp binder prs row `{stamp_label}` + status pr-open{box_note}{trace_note}")
elif written:
    print(f"stamp-pr-open: binder stamped ({stamp_label}, status pr-open{box_note}{trace_note})")
else:
    print("stamp-pr-open: binder no change (idempotent)")

try:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
finally:
    os.close(lock_fd)
PY
)

# Human output (strip the internal `committed:` line from commit_transaction).
printf '%s\n' "$STAMP_OUT" | grep -vE '^committed:'

# Stage the per-ticket ledger for commit (F2: committed so CI replays it).
# commit_transaction wrote it (in-python); stage if present.
TICKET_ID=$(basename "$(dirname "$BINDER")" | sed -n 's/^\(tkt-[1-9][0-9]*\)-.*/\1/p')
LATTICE_HOME_DIR=$(dirname "$(dirname "$(dirname "$BINDER")")")
LEDGER_FILE="$LATTICE_HOME_DIR/.transition-ledger/${TICKET_ID:-unknown}.jsonl"
[[ -f "$LEDGER_FILE" ]] && git add "$LEDGER_FILE" 2>/dev/null || true

# --- Mirror binder-checked acceptance into the GitHub issue -------------------
if [[ -z "$ISSUE_M" ]]; then
  echo "stamp-pr-open: no issue number (no --issue; binder github row unparsable) — issue sync skipped"
  exit 0
fi

# Checked binder acceptance items, one per line: "<ordinal>\t<A-id or ->\t<text>".
# Ordinals count ALL checkbox items in the binder's Acceptance section, so a
# checked item keeps its position for the id-less ordinal fallback.
# Under --check-all every item counts as checked (the stamp above checked them;
# in --dry-run the file is untouched, so the mode flag keeps the report honest).
CHECKED_ITEMS=$(python3 - "$BINDER" "$CHECK_ALL_MODE" <<'PY'
import re, sys

s = open(sys.argv[1], encoding="utf-8").read()
check_all = sys.argv[2] == "check-all"
m = re.search(r'^#{2,4} Acceptance\b.*?\n(.*?)(?=\n#{1,4} |\Z)', s, re.DOTALL | re.MULTILINE)
if not m:
    raise SystemExit(0)
ordinal = 0
for line in m.group(1).splitlines():
    box = re.match(r'^\s*- \[( |x|X)\] +(.*)$', line)
    if not box:
        continue
    ordinal += 1
    if check_all or box.group(1) in ("x", "X"):
        text = box.group(2).strip()
        mid = re.match(r'\*\*(A[0-9]+)\*\*', text)
        print(f"{ordinal}\t{mid.group(1) if mid else '-'}\t{text}")
PY
)

if [[ -z "$CHECKED_ITEMS" ]]; then
  echo "stamp-pr-open: no checked binder acceptance items — issue sync skipped"
  exit 0
fi

# gh failures on the issue side are soft: the binder stamp above already
# happened, and an unreachable issue must not sink the PR flow (decision-policy:
# never block). A warning is loud enough for the morning review.
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/stamp-pr-open.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

if $ADOPTED; then
  # Adopted / hand-created issue bodies are append-only: ONE comment, deduped
  # by a hidden marker so re-runs post nothing.
  MARKER="<!-- lattice:stamp-pr-open pr-$PR_N -->"
  # Dedup reads fail CLOSED: if gh errors or returns unparseable JSON we must
  # not post blind — a duplicate comment breaks the "re-runs post nothing"
  # contract above. Skip posting with a warning; the PR flow itself stays
  # unblocked (exit 0) per the decision-policy note at the top of this block.
  # (Known window: gh returns only the ~100 latest comments, so a marker older
  # than that still re-posts — acceptable; transient-error dupes were the
  # common case and are now closed.)
  if ! COMMENTS_JSON=$(gh issue view "$ISSUE_M" ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json comments 2>/dev/null) \
    || [[ -z "$COMMENTS_JSON" ]]; then
    echo "stamp-pr-open: WARNING — could not read issue #$ISSUE_M comments for dedup; comment post skipped (fail-closed: re-run once gh recovers)" >&2
    exit 0
  fi
  DEDUP_RC=0
  printf '%s' "$COMMENTS_JSON" | MARKER="$MARKER" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
    # any shape problem (non-object, non-dict comment, …) is unreadable input:
    marker = os.environ["MARKER"]
    found = any(marker in (c.get("body") or "") for c in (d.get("comments") or []))
except Exception:
    sys.exit(2)
sys.exit(0 if found else 1)
' || DEDUP_RC=$?
  if [[ "$DEDUP_RC" -eq 0 ]]; then
    echo "stamp-pr-open: issue #$ISSUE_M already carries the pr-$PR_N comment (idempotent)"
    exit 0
  elif [[ "$DEDUP_RC" -eq 2 ]]; then
    echo "stamp-pr-open: WARNING — issue #$ISSUE_M comments JSON unparseable; comment post skipped (fail-closed)" >&2
    exit 0
  fi
  {
    printf '%s\n\n' "$MARKER"
    printf 'PR pr-%s — %s is open for this ticket. Binder acceptance checked so far:\n\n' "$PR_N" "$PR_URL"
    printf '%s\n' "$CHECKED_ITEMS" | while IFS=$'\t' read -r _ _ text; do
      printf -- '- [x] %s\n' "$text"
    done
    printf '\n(adopted/hand-created issue body is append-only — checkboxes not edited)\n'
  } >"$TMP_DIR/comment.md"
  if $DRY_RUN; then
    echo "stamp-pr-open: DRY-RUN — would post acceptance comment on issue #$ISSUE_M (adopted binder; body untouched)"
    exit 0
  fi
  if gh issue comment "$ISSUE_M" ${GH_ARGS[@]+"${GH_ARGS[@]}"} --body-file "$TMP_DIR/comment.md" >/dev/null 2>&1; then
    echo "stamp-pr-open: adopted binder — posted acceptance comment on issue #$ISSUE_M (body untouched)"
  else
    echo "stamp-pr-open: WARNING — could not comment on issue #$ISSUE_M (gh auth? wrong repo?)" >&2
  fi
  exit 0
fi

BODY_JSON=$(gh issue view "$ISSUE_M" ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json body 2>/dev/null || true)
if [[ -z "$BODY_JSON" ]]; then
  echo "stamp-pr-open: WARNING — could not read issue #$ISSUE_M body; issue sync skipped" >&2
  exit 0
fi
printf '%s' "$BODY_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sys.stdout.write(d.get("body") or "")
' >"$TMP_DIR/body.md"

# Check matching boxes: A-id match first, ordinal fallback for id-less items.
# One-directional (check only); prints "changed:<n>"; new body in body.new.md.
# Items travel via env: `python3 -` takes its script on stdin, so a pipe would
# be swallowed by the heredoc.
SYNC_OUT=$(CHECKED_ITEMS="$CHECKED_ITEMS" python3 - "$TMP_DIR/body.md" "$TMP_DIR/body.new.md" <<'PY'
import os, re, sys

body_path, out_path = sys.argv[1:3]
items = []
for line in os.environ["CHECKED_ITEMS"].splitlines():
    if not line.strip():
        continue
    ordinal, aid, text = line.split("\t", 2)
    items.append((int(ordinal), None if aid == "-" else aid, text))

body = open(body_path, encoding="utf-8").read()
m = re.search(r'^#{2,4} Acceptance\b.*?\n(.*?)(?=\n#{1,4} |\Z)', body, re.DOTALL | re.MULTILINE)
if not m:
    print("no-acceptance-section")
    raise SystemExit(0)

section = m.group(1)
lines = section.splitlines(keepends=True)
boxes = []  # (line_index, checked, text)
for i, line in enumerate(lines):
    b = re.match(r'^(\s*- \[)( |x|X)(\] +)(.*?)(\s*)$', line, re.DOTALL)
    if b:
        boxes.append((i, b.group(2) in ("x", "X"), b.group(4)))

changed = 0
for ordinal, aid, _text in items:
    target = None
    if aid:
        for idx, (li, checked, text) in enumerate(boxes):
            if re.search(rf'(\*\*{aid}\*\*|\b{aid}\b)', text):
                target = idx
                break
    elif ordinal <= len(boxes):
        target = ordinal - 1
    if target is None:
        continue
    li, checked, _ = boxes[target]
    if not checked:
        lines[li] = re.sub(r'^(\s*- \[) (\])', r'\1x\2', lines[li])
        boxes[target] = (li, True, boxes[target][2])
        changed += 1

new_body = body[:m.start(1)] + "".join(lines) + body[m.end(1):]
open(out_path, "w", encoding="utf-8").write(new_body)
print(f"changed:{changed}")
PY
)

case "$SYNC_OUT" in
  no-acceptance-section)
    echo "stamp-pr-open: issue #$ISSUE_M has no Acceptance section — issue sync skipped"
    ;;
  changed:0)
    echo "stamp-pr-open: issue #$ISSUE_M acceptance already in sync (idempotent)"
    ;;
  changed:*)
    N_CHANGED=${SYNC_OUT#changed:}
    if $DRY_RUN; then
      echo "stamp-pr-open: DRY-RUN — would check $N_CHANGED acceptance box(es) on issue #$ISSUE_M"
    elif gh issue edit "$ISSUE_M" ${GH_ARGS[@]+"${GH_ARGS[@]}"} --body-file "$TMP_DIR/body.new.md" >/dev/null 2>&1; then
      echo "stamp-pr-open: checked $N_CHANGED acceptance box(es) on issue #$ISSUE_M"
    else
      echo "stamp-pr-open: WARNING — could not edit issue #$ISSUE_M body; issue sync skipped" >&2
    fi
    ;;
  *)
    echo "stamp-pr-open: WARNING — unexpected sync result: $SYNC_OUT" >&2
    ;;
esac

exit 0
