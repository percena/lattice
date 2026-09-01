#!/usr/bin/env bash
# Scripted owner of the `fix_cycles` counter + the pr-open → rework transition.
#
# The review-fix loop is bounded (ADR-004 §5 cap ≤2). Before this script the
# counter was template-declared but written by NO core-loop script — a pure
# six-skill loop left it 0 forever, and the cap had no defined cap-exit
# (rev-20260829-160834Z F4b/F5). This script is the procedural stamp point:
# finish-work's mini-review Hold path and the review-delivery --with-review fix
# loop both call it when findings are returned, so the counter is owned by one
# script, not agent prose.
#
# One call performs the pr-open → rework transition AND the fix_cycles bump,
# atomically (locked + atomic replace, finish-ledger/stamp-pr-open conventions):
#   - status pr-open → rework (the FSM edge; findings become the new brief,
#     recorded by the caller as a binder note + PR review threads)
#   - fix_cycles +1 (missing row = 0, lazy migration; the row is created if absent)
#
# Cap-exit (ADR-007 five-piece hard rule — spc-186 A6/A8):
#   - check    : this script counts fix_cycles and refuses a bump beyond ≤2
#   - message  : on cap-hit, the binder stays rework, fix_cycles holds at 2,
#                and a CAP-HIT trace forces the `deep-review` triage class
#                (human) before any further fix cycle — no auto-retry
#   - escape   : --extend-budget --reason "<operator-adjudicated rationale>"
#                authorizes exactly one more cycle (human, double-confirm;
#                no agent self-adjudication — ADR-007 §5b/5c)
#   - trace    : binder ## Decision journal (cap-hit entry or escape entry:
#                rule id, reason, authorizer, timestamp)
#   - metric   : the fix_cycles row itself (surfaced in the morning digest)
#
# Idempotent on the cap-hit binder: re-running without --extend-budget reprints
# the CAP-HIT message and mutates nothing.
#
# Usage:
#   bump-fix-cycle.sh --binder <path> [--note "<return brief>"]
#                     [--extend-budget --reason "<operator rationale>"] [--dry-run]
#   Exits 0 on stamp / cap-hit (routing decision, not failure); 1 on guard
#   refusal or IO failure; 2 on usage.
set -euo pipefail

# Resolve the physical installed script directory through symlink redirects
# (tkt-239 — same resolve_script_dir pattern as ensure-lattice.sh): lexical
# BASH_SOURCE dirname would let a consumer checkout place a fake
# ensure-python3.sh beside a symlink to this trusted script and execute it.
resolve_script_dir() {
  local source="$1"
  local dir target
  while [[ -L "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    target="$(readlink "$source")"
    if [[ "$target" == /* ]]; then
      source="$target"
    else
      source="$dir/$target"
    fi
  done
  cd -P "$(dirname "$source")" && pwd
}

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
bash "$(resolve_script_dir "${BASH_SOURCE[0]}")/ensure-python3.sh" || exit 1

BINDER=""
NOTE=""
EXTEND_BUDGET=false
EXTEND_REASON=""
DRY_RUN=false

usage() {
  cat >&2 <<'EOF'
Usage: bump-fix-cycle.sh --binder <path> [--note "<return brief>"]
                         [--extend-budget --reason "<operator rationale>"] [--dry-run]

Scripted owner of fix_cycles + the pr-open → rework transition (spc-186 A6/A8).
Called by finish-work mini-review Hold and review-delivery --with-review fix
loop when findings are returned. Stamps status → rework AND bumps fix_cycles in
one atomic write. Cap ≤2 (ADR-004 §5); exceeding it forces deep-review.

  --binder        path to binder README.md (required).
  --note          optional return-brief line appended to the journal trace
                  (the findings being returned; the caller records the full
                  brief as a binder note + PR review threads).
  --extend-budget operator-adjudicated escape: authorize ONE more fix cycle
                  past the ≤2 cap. Requires --reason; journals a structured
                  trace (ADR-007 §5b; no agent self-adjudication).
  --reason        rationale for --extend-budget (required with that flag).
  --dry-run       report what would change; mutate nothing.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binder) BINDER="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    --extend-budget) EXTEND_BUDGET=true; shift ;;
    --reason) EXTEND_REASON="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ -z "$BINDER" ]] && { echo "Error: --binder is required" >&2; usage; }
if [[ "$EXTEND_BUDGET" == true && -z "$EXTEND_REASON" ]]; then
  echo "Error: --extend-budget requires --reason \"<operator-adjudicated rationale>\"" >&2
  usage
fi

if [[ ! -f "$BINDER" ]]; then
  echo "bump-fix-cycle: no binder at $BINDER — skip (ticket-only flow)" >&2
  exit 0
fi

# --- Binder path containment (same law as stamp-pr-open.sh) -------------------
# Resolve, refuse symlinked components, require a regular file under the
# repo's .lattice/ tree (agent-derived path; a cloned repo can ship a symlink).
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

STAMP_MODE=$($DRY_RUN && echo "dry-run" || echo "write")
EXTEND_MODE=$($EXTEND_BUDGET && echo "extend" || echo "no-extend")
BINDER_ROWS_LIB="$(resolve_script_dir "${BASH_SOURCE[0]}")/lib"
STAMP_OUT=$(BINDER_ROWS_LIB="$BINDER_ROWS_LIB" python3 - "$BINDER" "$STAMP_MODE" "$EXTEND_MODE" "$EXTEND_REASON" "$NOTE" <<'PY'
import datetime, sys, re, os, stat, fcntl, importlib.util

sys.path.insert(0, os.environ["BINDER_ROWS_LIB"])
import status_vocab
# spc-297: import transition-api for in-lock single-write atomicity.
_ta_path = os.path.join(os.environ["BINDER_ROWS_LIB"], "..", "transition-api.py")
_ta_spec = importlib.util.spec_from_file_location("transition_api", _ta_path)
_ta = importlib.util.module_from_spec(_ta_spec); _ta_spec.loader.exec_module(_ta)

binder, mode, extend_mode, extend_reason, note = sys.argv[1:6]
dry_run = mode == "dry-run"
extend_budget = extend_mode == "extend"

# Exclusive lock on the containing directory for the whole read-modify-write
# (stable inode across atomic replaces; no untracked lock artifact).
lock_dir = os.path.dirname(os.path.abspath(binder)) or "."
lock_fd = os.open(lock_dir, os.O_RDONLY)
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
except OSError as exc:
    os.close(lock_fd)
    raise SystemExit(f"bump-fix-cycle: cannot lock binder directory: {exc}")

s = open(binder, encoding="utf-8").read()
orig = s

CAP = 2  # ADR-004 §5 review-fix cap

def append_journal_trace(text, entry):
    """Append a dated bullet to ## Decision journal, creating the section if
    absent (mirrors ratify.sh / stamp-pr-open.sh). Returns the new text."""
    m_hdr = re.search(r'^## Decision journal[ \t]*\n', text, re.MULTILINE)
    if m_hdr:
        body_start = m_hdr.end()
        tail = text[body_start:]
        bnd = re.search(r'\n## ', tail)
        body = tail[:bnd.start()] if bnd else tail
        trailing = tail[bnd.start():] if bnd else ""
        stripped = body.strip("\n")
        new_body = (stripped + "\n" + entry + "\n") if stripped else (entry + "\n")
        return text[:body_start] + "\n" + new_body + trailing
    anchor = re.search(r'\n(## (?:Notes|References|Lineage|Finish|Pending decisions|Attempts)\b)', text)
    block = f"\n## Decision journal\n\n{entry}\n"
    if anchor:
        return text[:anchor.start()] + block + text[anchor.start():]
    return text.rstrip("\n") + "\n" + block

# --- read current status + fix_cycles ----------------------------------------
status_row = re.compile(r'(\| status \|)\s*(.*?)\s*(\|)')
m_status = status_row.search(s)
if not m_status:
    print("bump-fix-cycle: REFUSED — binder has no `| status |` row; cannot stamp rework", file=sys.stderr)
    sys.exit(1)
prior = m_status.group(2).strip()

fc_row = re.compile(r'(\| fix_cycles \|)\s*(.*?)\s*(\|)')
m_fc = fc_row.search(s)
has_fc_row = bool(m_fc)
fc_val = 0
if m_fc:
    digits = re.match(r'\s*([0-9]+)', m_fc.group(2))
    if digits:
        fc_val = int(digits.group(1))

if status_vocab.is_terminal(prior):
    print(f"bump-fix-cycle: REFUSED — binder status is `{prior}` (terminal); rework does not apply", file=sys.stderr)
    sys.exit(1)

stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
note_suffix = f" — brief: {note}" if note else ""

# spc-297: single-write atomicity. The pr-open → rework status flip +
# Decision-journal trace + `updated` + ledger land in ONE `commit_transaction`
# merged with the fix_cycles field already in `s`, called inside this dir lock
# (cures the double-increment-on-crash regression — fix_cycles + status flip
# are now one transaction, not two writes). The rework → rework escape (no
# real status flip — rework→rework is not a legal edge) keeps the original
# single in-python write: fix_cycles bump + journal trace, no
# prepare/commit_transaction.
flip_journal = None   # set by pr-open paths → drives prepare_commit_text
flip_owner = "system"
flip_reason = "review-hold"

def set_flip(reason, owner, journal_text):
    """Record the flip params for the post-dispatch prepare_commit_text call
    (pr-open → rework only). No-op effect in dry-run (no commit_transaction)."""
    global flip_journal, flip_owner, flip_reason
    flip_reason = reason
    flip_owner = owner
    flip_journal = journal_text

def bump_fix_cycles():
    """Bump fc_val and write the fix_cycles row (in-place bump or insert after
    the status row for lazy migration)."""
    global s, fc_val
    fc_val = fc_val + 1
    if has_fc_row:
        s = fc_row.sub(rf'\1 {fc_val} \3', s, count=1)
    else:
        s = status_row.sub(
            lambda mm: mm.group(0) + f"\n| fix_cycles | {fc_val} |", s, count=1)

# --- cap-hit: third rework requested (fix_cycles at CAP, prior == pr-open) ---
# The binder flips to rework (the findings are real), but fix_cycles HOLDS at
# CAP and a CAP-HIT trace forces deep-review before any further fix cycle. No
# auto-retry (spc-186 A6 cap-exit). fix_cycles is not written here (holds);
# the flip + CAP-HIT trace go through commit.
def write_cap_hit():
    entry = (
        f"- {stamp} — CAP-HIT: fix_cycles at cap ({CAP}); third rework requested "
        f"from `{prior}` → rework. Binder holds at fix_cycles {CAP} and the "
        f"triage class is FORCED to `deep-review` (human) before any further "
        f"fix cycle (ADR-004 §5 cap; ADR-007 §4 five-piece; spc-186 A6). "
        f"To authorize one more cycle: --extend-budget --reason "
        f"\"<operator-adjudicated rationale>\"{note_suffix}"
    )
    set_flip("review-hold (cap-hit)", "system", entry)

# --- escape: operator authorizes one more cycle (human, double-confirm) ------
def write_escape():
    global s, fc_val
    bump_fix_cycles()
    entry = (
        f"- {stamp} — ESCAPE: fix_cycles bumped to {fc_val} (past cap {CAP}) "
        f"under operator-adjudicated --extend-budget on a `{prior}` → rework "
        f"transition (reason: {extend_reason}) "
        f"[operator-adjudicated — ADR-007 §5b; no agent self-adjudication]{note_suffix}"
    )
    if prior == "pr-open":
        # real flip → prepare_commit_text + commit_transaction (single write)
        set_flip("review-hold (extend-budget)", "human", entry)
    else:
        # rework → rework (no legal edge): single-write fix_cycles + journal,
        # no prepare/commit (no status flip to record).
        s = append_journal_trace(s, entry)

# --- normal bump: within cap -----------------------------------------------
def write_normal():
    global fc_val
    bump_fix_cycles()
    entry = (
        f"- {stamp} — fix cycle {fc_val}: `{prior}` → rework "
        f"(fix_cycles {fc_val}; cap ≤{CAP}; ADR-004 §5){note_suffix}"
    )
    set_flip("review-hold", "system", entry)

# --- dispatch -------------------------------------------------------------
# Legal sources for the pr-open → rework transition: `pr-open` (the default),
# and `rework` ONLY under the --extend-budget escape (re-stamping a cap-hit
# binder that already transitioned to rework). Any other status is refused.
if prior == "pr-open":
    if fc_val + 1 > CAP and not extend_budget:
        write_cap_hit()
        outcome = "cap-hit"
    elif extend_budget:
        write_escape()
        outcome = "escape"
    else:
        write_normal()
        outcome = "normal"
elif prior == "rework":
    # A rework binder is one of:
    #  - a cap-hit binder already at the cap-exit state (fix_cycles >= CAP):
    #    idempotent — re-running without --extend-budget reprints the CAP-HIT
    #    message and mutates nothing (the deep-review forcing is re-surfaced,
    #    not re-stamped). The escape channel re-runs here too.
    #  - an in-progress rework below the cap: an illegal double-rework without
    #    a pr-open in between. Refused so the cycle must go
    #    rework → in-progress → pr-open → rework.
    if fc_val >= CAP and not extend_budget:
        outcome = "cap-hit-idempotent"
    elif not extend_budget:
        print(
            f"bump-fix-cycle: REFUSED — binder status is already `rework` "
            f"(fix_cycles {fc_val} < cap {CAP}). A new fix cycle requires "
            f"returning to pr-open first (rework → in-progress → pr-open → "
            f"rework), or an operator-adjudicated --extend-budget --reason "
            f"\"<rationale>\" escape (ADR-007 §5b).",
            file=sys.stderr,
        )
        sys.exit(1)
    else:
        write_escape()
        outcome = "escape"
else:
    print(
        f"bump-fix-cycle: REFUSED — binder status is `{prior}`; the pr-open → "
        f"rework transition requires status `pr-open` (or `rework` under "
        f"--extend-budget). Did you mean to stamp `pr-open` first?",
        file=sys.stderr,
    )
    sys.exit(1)

# --- single-write atomic transaction (spc-297) ---------------------------
TICKET_ID = ""
m_tid = re.match(r'^(tkt-[1-9][0-9]*)', os.path.basename(os.path.dirname(binder)))
if m_tid:
    TICKET_ID = m_tid.group(1)
if dry_run:
    pass  # no write; DRY-RUN message below
elif flip_journal is not None:
    # pr-open → rework: prepare_commit_text merges the status flip + journal +
    # updated into `s` (which already carries the fix_cycles bump/hold), then
    # commit_transaction writes binder + ledger atomically (single write — no
    # double-increment-on-crash window).
    rc, nt, ledentry = _ta.prepare_commit_text(
        s, TICKET_ID, "rework", flip_owner, flip_reason,
        journal_entry=flip_journal)
    if rc != 0:
        print("bump-fix-cycle: WARN — transition refused (non-blocking; "
              "validator will catch); fix_cycles written but status not "
              "flipped", file=sys.stderr)
    else:
        rc2 = _ta.commit_transaction(binder, nt, ledentry)
        if rc2 != 0:
            print("bump-fix-cycle: WARN — transaction failed (non-blocking; "
                  "validator will catch)", file=sys.stderr)
elif s != orig:
    # rework → rework escape (fix_cycles + journal, no status flip) — write `s`
    # directly (no ledger; rework→rework is not a recorded edge).
    import tempfile
    d = os.path.dirname(os.path.abspath(binder)) or "."
    fmode = os.stat(binder).st_mode
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".bump-fix-cycle.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(s)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, stat.S_IMODE(fmode))
        os.replace(tmp, binder)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
# else: cap-hit-idempotent (rework at cap, no extend) → no mutation.

try:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
finally:
    os.close(lock_fd)

# --- report ---------------------------------------------------------------
if outcome == "cap-hit":
    msg = (
        f"bump-fix-cycle: CAP-HIT — fix_cycles holds at {CAP} (third rework "
        f"requested from `{prior}` → rework); triage class FORCED to "
        f"`deep-review` (human). To authorize one more cycle: "
        f"--extend-budget --reason \"<operator-adjudicated rationale>\""
    )
elif outcome == "cap-hit-idempotent":
    msg = (
        f"bump-fix-cycle: CAP-HIT — fix_cycles holds at {fc_val} (binder "
        f"already rework at cap); triage class FORCED to `deep-review` "
        f"(human). To authorize one more cycle: --extend-budget --reason "
        f"\"<operator-adjudicated rationale>\""
    )
elif outcome == "escape":
    msg = (
        f"bump-fix-cycle: ESCAPE — fix_cycles bumped to {fc_val} (past cap {CAP}) "
        f"under operator-adjudicated --extend-budget ({prior} → rework)"
    )
else:
    msg = (
        f"bump-fix-cycle: stamped rework + fix_cycles {fc_val} (cap ≤{CAP}; "
        f"{prior} → rework)"
    )

# A1.3: cap-hit (pr-open) no longer mutates the binder in-python (commit does
# the flip + trace), so s == orig there — but it is NOT an idempotent no-op.
# Only cap-hit-idempotent (rework at cap, no extend) is a true no-op. So the
# message is outcome-driven, not s==orig-driven.
if dry_run:
    print(f"bump-fix-cycle: DRY-RUN — would {msg}")
else:
    print(msg)
PY
)

# Preserve human output (strip the internal `committed:` line).
printf '%s\n' "$STAMP_OUT" | grep -vE '^committed:' || true

# Stage the per-ticket ledger for commit (F2). commit_transaction wrote it.
TICKET_ID=$(basename "$(dirname "$BINDER")" | sed -n 's/^\(tkt-[1-9][0-9]*\)-.*/\1/p')
LATTICE_HOME_DIR="$(dirname "$(dirname "$(dirname "$BINDER")")")"
LEDGER_FILE="$LATTICE_HOME_DIR/.transition-ledger/${TICKET_ID:-unknown}.jsonl"
[[ -f "$LEDGER_FILE" ]] && git add "$LEDGER_FILE" 2>/dev/null || true

exit 0
