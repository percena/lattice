#!/usr/bin/env bash
# ratify.sh — single-commit ratification of a parked binder decision (FSM-4 Option A).
#
# Writes the decision into the binder's `## Decision journal` AND flips
# status: parked → queued in one git commit. Narrows the crash window
# between the two writes to a single reviewable commit (ADR-004 amd
# tkt-136 Option A — "single-commit, crash window narrowed, not eliminated").
#
# Recovery recipe: if `git commit` fails AFTER the atomic `os.replace` succeeds
# (e.g. a hook rejects the commit), the binder is left mutated on disk (status
# `queued`) but uncommitted. A re-run refuses because the status is no longer
# `parked`. To recover, discard the mutation and re-run:
#   git checkout -- <binder> && git restore --staged <binder>
# Full transactional rollback is NOT implemented (ADR-004 design tradeoff).
#
# When --pending <substring> is supplied, the matching bullet line under
# `## Pending decisions` is settled (removed) — the decision is now journaled,
# so it is no longer pending. Exactly one match is required; zero or multiple
# matches fail before any mutation. Omit --pending to ratify without settling.
#
# The read-modify-write is a contained Python stdlib transaction (no shell/sed
# in-place editing): the binder path is resolved and symlink-checked under the
# repo's `.lattice/tickets/` tree, the directory is flock'd, the file is
# re-read under the lock, the new content is built in memory and atomically
# replaced (temp + fsync + rename). The Git index is checked BEFORE mutation
# and unrelated pre-staged paths are refused; only the binder is committed.
#
# Usage:
#   ratify.sh --binder <path/to/README.md> --decision "<decision text>" [--pending "<substring>"]
#   ratify.sh --binder .lattice/tickets/tkt-42-foo/README.md \
#       --decision "use retry-lib not backoff-lib (source: preference retry-at-most-once)" \
#       --pending "retry-lib vs backoff-lib"
#
# Exit: 0 = ratified (committed), 1 = error, 2 = usage
set -euo pipefail

BINDER=""
DECISION=""
PENDING=""

usage() { cat <<'USAGE'
Usage: ratify.sh --binder <README.md> --decision "<text>" [--pending "<substring>"]
  --binder    Path to the ticket binder README.md (required)
  --decision  Decision text to append to ## Decision journal (required)
  --pending   Substring identifying a single bullet under ## Pending decisions
              to settle (remove). Optional; omit to ratify without settling.
              Exactly one match is required when supplied.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binder)   BINDER="${2:?}"; shift 2 ;;
    --decision) DECISION="${2:?}"; shift 2 ;;
    --pending)  PENDING="${2:?}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Error: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$BINDER" ]]   || { echo "Error: --binder required" >&2; usage; exit 2; }
[[ -n "$DECISION" ]] || { echo "Error: --decision required" >&2; usage; exit 2; }
if [[ "$DECISION" == *$'\n'* ]]; then
  echo "Error: --decision must be a single line (no embedded newlines)" >&2
  exit 2
fi

# --- Locate the repo root from the binder's own directory -------------------
# A binder outside any git worktree cannot be contained or committed safely.
BINDER_REPO_ROOT=$(git -C "$(dirname "$BINDER")" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$BINDER_REPO_ROOT" ]]; then
  echo "Error: --binder is not inside a git worktree: $BINDER" >&2
  exit 1
fi

# --- Contain the binder path (resolve, reject symlinks, require .lattice/tickets) ---
# The path is agent-derived; a cloned repo can ship a symlinked binder. Contain
# it exactly the way finish-ledger.sh / upload-github-asset.sh do: lstat every
# component below the repo root so no ancestor can redirect, refuse symlinks,
# require a regular file under <repo>/.lattice/tickets/. No env escape hatch.
if ! BINDER=$(RATIFY_BINDER="$BINDER" RATIFY_ROOT="$BINDER_REPO_ROOT" python3 - <<'RATIFYPATH'
import os, stat, sys

binder = os.path.abspath(os.environ["RATIFY_BINDER"])
root = os.path.realpath(os.environ["RATIFY_ROOT"])
home = os.path.join(root, ".lattice", "tickets")

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
RATIFYPATH
); then
  exit 1
fi

BINDER_DIR=$(dirname "$BINDER")
BINDER_NAME=$(basename "$BINDER_DIR")

# --- Tracked-file precondition (A2: untracked binder must fail) -------------
if ! git -C "$BINDER_REPO_ROOT" ls-files --error-unmatch -- "$BINDER" >/dev/null 2>&1; then
  echo "Error: binder is not tracked by git (run git add first or pick a real binder): $BINDER" >&2
  exit 1
fi

RELATIVE_BINDER=$(git -C "$BINDER_REPO_ROOT" ls-files --full-name -- "$BINDER")

# --- Unrelated pre-staged changes: refuse BEFORE mutation (A2) -------------
# Map every staged path to its repo-relative form and compare against the
# binder's relative path. The binder itself may be pre-staged (we re-stage it
# after the atomic rewrite); any OTHER staged path is refused. Portable loop
# (no mapfile/readarray: macOS system bash is 3.2).
while IFS= read -r staged; do
  [[ -z "$staged" ]] && continue
  if [[ "$staged" != "$RELATIVE_BINDER" ]]; then
    echo "Error: refusing to ratify with unrelated pre-staged path: $staged" >&2
    echo "  commit or unstage it first; ratify commits only the binder" >&2
    exit 1
  fi
done < <(git -C "$BINDER_REPO_ROOT" diff --cached --name-only || true)

echo "ratify: $BINDER_NAME — ratifying parked binder (status: parked → queued)"

# --- Contained read-modify-write (lock + atomic replace) -------------------
RATIFY_BINDER="$BINDER" RATIFY_DECISION="$DECISION" RATIFY_PENDING="$PENDING" \
  python3 - <<'PY'
import datetime, fcntl, os, re, stat, sys, tempfile

binder   = os.environ["RATIFY_BINDER"]
decision = os.environ["RATIFY_DECISION"]
pending  = os.environ["RATIFY_PENDING"]  # "" ⇒ no settlement
stamp    = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
entry    = f"- {decision} (ratified {stamp})"

# Exclusive lock on the containing directory: its inode stays stable while the
# binder is atomically replaced (unlike a lock on the file being renamed), and
# it leaves no untracked lock artifact. Mirrors finish-ledger.sh.
lock_dir = os.path.dirname(os.path.abspath(binder)) or "."
lock_fd = os.open(lock_dir, os.O_RDONLY)
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
except OSError as exc:
    os.close(lock_fd)
    raise SystemExit(f"ratify: cannot lock binder directory: {exc}")

try:
    s = open(binder, encoding="utf-8").read()
    orig = s

    # --- Precondition: status must be exactly 'parked' (re-checked under lock) ---
    # Use [ \t] (not \s) so the match cannot eat newlines and collapse the
    # blank line that separates the field table from the next section.
    m_status = re.search(r'^\| status \|[ \t]*([^|]+?)[ \t]*\|[ \t]*$', s, re.MULTILINE)
    if not m_status:
        print("Error: binder has no `| status | … |` field row", file=sys.stderr)
        raise SystemExit(1)
    current_status = m_status.group(1).strip()
    if current_status != "parked":
        print(f"Error: binder status is '{current_status}', expected 'parked'. "
              f"ratify.sh only ratifies parked binders (rerun is fail-safe).", file=sys.stderr)
        raise SystemExit(1)

    # --- 1. Insert dated decision into ## Decision journal ------------------
    # Section body runs from after the header newline to the next `## ` heading
    # or EOF. Reconstruct preserving the blank-line convention (header, blank
    # line, bullets, blank line, next heading). Works whether the journal is at
    # EOF or followed by another section.
    m_hdr = re.search(r'^## Decision journal[ \t]*\n', s, re.MULTILINE)
    if not m_hdr:
        print("Error: binder has no `## Decision journal` section", file=sys.stderr)
        raise SystemExit(1)
    body_start = m_hdr.end()
    tail = s[body_start:]
    bnd = re.search(r'\n## ', tail)
    if bnd:
        body, trailing = tail[:bnd.start()], tail[bnd.start():]
    else:
        body, trailing = tail, ""
    stripped = body.strip("\n")
    if stripped:
        new_body = stripped + "\n" + entry + "\n"
    else:
        new_body = entry + "\n"
    s = s[:body_start] + "\n" + new_body + trailing

    # --- 2. Settle the selected pending decision (when --pending supplied) ---
    if pending:
        m_pend = re.search(r'^## Pending decisions[ \t]*\n', s, re.MULTILINE)
        if not m_pend:
            print("Error: --pending supplied but binder has no `## Pending decisions` section",
                  file=sys.stderr)
            raise SystemExit(1)
        p_start = m_pend.end()
        ptail = s[p_start:]
        pbnd = re.search(r'\n## ', ptail)
        if pbnd:
            p_body, p_trailing = ptail[:pbnd.start()], ptail[pbnd.start():]
        else:
            p_body, p_trailing = ptail, ""
        # Bullet lines within the pending section (non-empty `- …` lines).
        lines = p_body.split("\n")
        bullets = [(i, ln) for i, ln in enumerate(lines) if re.match(r'^\s*-\s+', ln)]
        matches = [ln for _, ln in bullets if pending in ln]
        if len(matches) == 0:
            print(f"Error: --pending substring matched no pending decision bullet: {pending!r}",
                  file=sys.stderr)
            raise SystemExit(1)
        if len(matches) > 1:
            print(f"Error: --pending substring matched {len(matches)} pending decision bullets; "
                  f"be more specific: {pending!r}", file=sys.stderr)
            raise SystemExit(1)
        # Remove the single matched bullet line (settle: it is now journaled).
        target = matches[0]
        out_lines = []
        removed = False
        for ln in lines:
            if not removed and ln == target:
                removed = True
                continue
            out_lines.append(ln)
        new_p_body = "\n".join(out_lines).strip("\n")
        # One leading newline (the header already consumed its own); when the
        # body is empty emit nothing extra so the section collapses to a single
        # blank line before the next heading.
        new_p = ("\n" + new_p_body + "\n") if new_p_body else ""
        s = s[:p_start] + new_p + p_trailing

    # --- 3. Flip status: parked → queued (field table) -----------------------
    # [ \t] (not \s) so the regex cannot swallow the row's trailing newline
    # and merge the table into the following section.
    s = re.sub(r'^(\| status \|)[ \t]*parked[ \t]*(\|)[ \t]*$', r'\1 queued \2', s, count=1, flags=re.MULTILINE)

    if s == orig:
        # No mutation should happen on a valid parked binder; if it did, don't write.
        print("ratify: no change (binder already ratified?)", file=sys.stderr)
        raise SystemExit(1)

    # Atomic replace: temp + fsync + rename. Preserve original mode.
    d = os.path.dirname(os.path.abspath(binder)) or "."
    mode = os.stat(binder).st_mode
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".ratify.", suffix=".tmp")
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
finally:
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
    finally:
        os.close(lock_fd)
PY

# --- 4. Single git commit (journal + status flip together) -----------------
# Stage only the binder, then commit only that pathspec — unrelated index
# entries (already refused above) cannot sneak into this commit.
git -C "$BINDER_REPO_ROOT" add -- "$RELATIVE_BINDER"
SUMMARY=$(printf '%s' "$DECISION" | head -c 72)
git -C "$BINDER_REPO_ROOT" commit -q -m "ratify(${BINDER_NAME}): ${SUMMARY}" -- "$RELATIVE_BINDER"

echo "ratify: done — single commit written (journal entry + parked → queued)"
