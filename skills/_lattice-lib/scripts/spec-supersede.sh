#!/usr/bin/env bash
# spec-supersede.sh — trip-time sweep of a superseded Spec's child binders.
#
# When a Spec is superseded (status -> superseded with superseded_by set),
# its still-active child binders learn they are obsolete ONLY at finish-work
# land-time (drift check) — potentially after a wasted night batch. That
# violates the trip-time honesty principle (tkt-136/137: stamp at trip time,
# not later). This script generalizes that principle to spec supersede:
# it stamps the superseded Spec's still-active child binders to
# `status: deferred` + `wait_reason: spec-superseded` AT supersede time.
#
# Invoked from create-spec's supersede path AFTER create-spec has flipped the
# old Spec's front matter (status: superseded + superseded_by: spc-N). This
# script does NOT flip the Spec status — that is create-spec's job; it sweeps
# the children. Precondition: the Spec is already superseded with a valid
# superseded_by link (refuses otherwise).
#
# Sweep policy (spc-186 A3; decision journaled in tkt-190):
#   STAMP -> deferred + spec-superseded: queued | in-progress | deferred
#     (in-progress is included so an agent mid-flight learns the work is
#      obsolete on its next binder read — stamping is non-destructive, it
#      marks, never kills a running process; the trip-time principle wins
#      over the "agent may be mid-flight" caution)
#     (an already-deferred binder is re-stamped: spec-superseded supersedes
#      the prior reason — the work is now obsolete, not just fuse-halted)
#   SKIP (terminal): closed (nothing to invalidate)
#   SKIP (side states): parked | stuck | rework — hold an external signal a
#     silent overwrite must not lose (ADR-007 sec.5b side-state guard). They
#     surface in morning triage for a human disposition under the supersede.
#   SKIP (open PR): pr-open — a live PR is a human decision (close? re-point?)
#     auto-deferring it would orphan the PR; surfaced in morning triage.
#   SKIP (legacy): open — coarse; migrated via the working enum first.
#   IDEMPOTENT: deferred + wait_reason already spec-superseded — no mutation.
#
# Each mutated binder is a single contained commit (ratify.sh pattern): locked
# read-modify-write (status flip + wait_reason set + journal entry + updated
# bump) in one atomic replace, then one git commit of ONLY that binder, so a
# crash between binders never corrupts a half-written one.
#
# finish-work's land-time Spec drift check remains as a backstop — the sweep
# is the trip-time stamp; the drift check catches anything the sweep missed.
#
# Usage:
#   spec-supersede.sh --spec <path/to/spc-N-slug.md> [--home <lattice home>] [--dry-run]
#
# Exit: 0 = sweep complete (>=0 binders stamped), 1 = error, 2 = usage
set -euo pipefail

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
bash "$(dirname "${BASH_SOURCE[0]}")/ensure-python3.sh" || exit 1

SPEC=""
HOME_DIR=""
DRY_RUN=false

usage() {
  cat >&2 <<'EOF'
Usage: spec-supersede.sh --spec <spc-N-slug.md> [--home <lattice home>] [--dry-run]
  --spec   path to the superseded Spec file (required, under <home>/specs/)
  --home   lattice home (default: <git toplevel>/.lattice)
  --dry-run report the sweep plan without mutating or committing
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec) SPEC="${2:-}"; shift 2 ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Error: unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$SPEC" ]] || { echo "Error: --spec required" >&2; usage; }

# --- Resolve the lattice lib (status_vocab + binder_rows) ------------------
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
SS_LIB="$SCRIPT_DIR/lib"
if [[ ! -f "$SS_LIB/status_vocab.py" ]]; then
  # Installed alongside a consumer skill — resolve via resolve-lattice-lib.sh
  RESOLVE="$SCRIPT_DIR/resolve-lattice-lib.sh"
  if [[ -f "$RESOLVE" ]]; then
    SS_LIB="$(bash "$RESOLVE")/lib"
  fi
fi
if [[ ! -f "$SS_LIB/status_vocab.py" ]]; then
  echo "Error: cannot locate lib/status_vocab.py beside $SCRIPT_DIR" >&2
  exit 1
fi

# --- Resolve lattice home + repo root (from the spec's own location) -------
# Derive from the spec path (like ratify.sh derives the repo root from the
# binder path), NOT from cwd — so a caller in a different checkout still sweeps
# the right home. --home overrides; otherwise <spec-repo>/.lattice.
SPEC_DIR="$(dirname "$SPEC")"
if [[ -z "$HOME_DIR" ]]; then
  if ROOT=$(git -C "$SPEC_DIR" rev-parse --show-toplevel 2>/dev/null); then
    HOME_DIR="$ROOT/.lattice"
  else
    HOME_DIR="$PWD/.lattice"
  fi
fi
REPO_ROOT="$(git -C "$SPEC_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

# --- Contain the spec path (absolute, under <home>/specs/, regular file) ----
if ! SPEC=$(SS_SPEC="$SPEC" SS_HOME="$HOME_DIR" python3 - <<'SSPATH'
import os, stat, sys
spec = os.path.abspath(os.environ["SS_SPEC"])
home = os.path.realpath(os.environ["SS_HOME"])
specs = os.path.join(home, "specs")
resolved = os.path.realpath(spec)
if os.path.commonpath([specs, resolved]) != specs:
    print(f"Error: spec must live under {specs}, got: {resolved}", file=sys.stderr)
    raise SystemExit(1)
if not os.path.isfile(resolved):
    print(f"Error: spec is not a regular file: {resolved}", file=sys.stderr)
    raise SystemExit(1)
print(resolved)
SSPATH
); then
  exit 1
fi

# --- Tracked-file precondition on the spec ---------------------------------
if ! git -C "$REPO_ROOT" ls-files --error-unmatch -- "$SPEC" >/dev/null 2>&1; then
  echo "Error: spec is not tracked by git: $SPEC" >&2
  exit 1
fi

# --- Unrelated pre-staged changes: refuse BEFORE mutation ------------------
while IFS= read -r staged; do
  [[ -z "$staged" ]] && continue
  echo "Error: refusing to sweep with unrelated pre-staged path: $staged" >&2
  echo "  commit or unstage it first; the sweep commits only child binders" >&2
  exit 1
done < <(git -C "$REPO_ROOT" diff --cached --name-only || true)

export SS_SPEC="$SPEC"
export SS_HOME="$HOME_DIR"
export SS_REPO_ROOT="$REPO_ROOT"
export SS_LIB="$SS_LIB"
export SS_DRY_RUN="$DRY_RUN"

# --- Sweep: contained read-modify-write per qualifying binder ---------------
# Python returns one mutated binder repo-relative path per line (after the
# STATUS marker line). Bash commits each one atomically below.
SWEEP_OUT=$(python3 - <<'PY'
import datetime, fcntl, glob, os, re, stat, subprocess, sys, tempfile

sys.path.insert(0, os.environ["SS_LIB"])
import status_vocab
import binder_rows

spec_path = os.environ["SS_SPEC"]
home = os.path.realpath(os.environ["SS_HOME"])
repo_root = os.path.realpath(os.environ["SS_REPO_ROOT"])
dry_run = os.environ.get("SS_DRY_RUN", "false").lower() == "true"

stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# --- Parse the Spec front matter -------------------------------------------
spec_text = open(spec_path, encoding="utf-8").read()

def fm_value(text, key):
    m = re.search(rf"^#{key}:\s*(\S.*?)\s*$", text, re.MULTILINE)
    # YAML front matter uses bare `key:` not `#key:`; match both the commented
    # template hint and the real front-matter line.
    return m.group(1).strip() if m else ""

def fm_field(text, key):
    m = re.search(rf"^{key}:\s*(.*?)\s*$", text, re.MULTILINE)
    return m.group(1).strip() if m else ""

sp_status = fm_field(spec_text, "status").strip().lower()
superseded_by = fm_field(spec_text, "superseded_by").strip()

# Precondition: spec must already be superseded with a valid superseded_by link.
if sp_status != "superseded":
    print(f"Error: spec status is '{sp_status}', expected 'superseded'. "
          f"Flip the Spec to superseded (create-spec) before sweeping children.",
          file=sys.stderr)
    sys.exit(1)
if not superseded_by or superseded_by.lower() in ("null", "none", "(none)"):
    print("Error: spec is superseded but superseded_by is unset/null. "
          "Set superseded_by: spc-N before sweeping.", file=sys.stderr)
    sys.exit(1)

# --- Collect the Spec's ticket ids (authoritative tickets: front matter) ---
tickets_raw = fm_field(spec_text, "tickets")
ticket_nums = sorted({int(n) for n in re.findall(r"tkt-([1-9][0-9]*)", tickets_raw)},
                     key=lambda n: n)
if not ticket_nums:
    print("spec-supersede: spec has no child tickets in its tickets: list — "
          "nothing to sweep", file=sys.stderr)
    print("SS_STATUS=empty")
    sys.exit(0)

# --- Sweep policy ----------------------------------------------------------
# STAMP these (still-active, no external signal to preserve):
STAMPABLE = {"queued", "in-progress", "deferred"}
# SKIP terminal / side-states / open-PR / legacy — surfaced in the report.

def first_table_block(text):
    lines, in_table = [], False
    for line in text.splitlines():
        if line.startswith("|"):
            in_table = True
            lines.append(line)
        elif in_table:
            break
    return "\n".join(lines)

def table_field(table, name):
    m = re.search(rf"^\|\s*{re.escape(name)}\s*\|\s*([^|]*?)\s*\|",
                 table, re.I | re.MULTILINE)
    return m.group(1).strip() if m else ""

mutated = []  # repo-relative binder paths
report = []   # (tkt_n, status, action, detail)

for n in ticket_nums:
    # Locate the binder directory: <home>/tickets/tkt-N-*/README.md (not archive)
    candidates = sorted(glob.glob(os.path.join(home, "tickets", f"tkt-{n}-*", "README.md")))
    candidates = [c for c in candidates if os.path.isfile(c)]
    if not candidates:
        report.append((n, "(none)", "skip", "no binder found under tickets/"))
        continue
    if len(candidates) > 1:
        report.append((n, "(none)", "skip",
                        f"ambiguous binder dir ({len(candidates)} matches)"))
        continue
    binder = os.path.realpath(candidates[0])
    binder_dir = os.path.dirname(binder)

    # --- Locked read-modify-write (lock BEFORE read — tkt-237 M1) ----------
    # The directory lock guards the WHOLE read-modify-write, not just the
    # replace. The prior code read the binder at :238, parsed, mutated, then
    # acquired flock only at the os.replace — a concurrent stamp
    # (queued->pr-open + prs entry) in that window was lost on overwrite
    # (read-before-lock TOCTOU). Acquire the exclusive lock BEFORE reading so
    # the parsed status/wait_reason are the latest on-disk values, and re-check
    # the idempotent/stampable predicates under the lock (compare
    # ratify.sh:186 which re-reads inside the lock).
    lock_fd = os.open(binder_dir, os.O_RDONLY)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
    except OSError as exc:
        os.close(lock_fd)
        print(f"Error: cannot lock binder directory for tkt-{n}: {exc}",
              file=sys.stderr)
        sys.exit(1)
    try:
        # Read binder + parse status / wait_reason from the first table block.
        s = open(binder, encoding="utf-8").read()
        table = first_table_block(s)
        status = table_field(table, "status").strip().lower()
        wait_reason = table_field(table, "wait_reason").strip()

        # Idempotent: already deferred via spec-superseded.
        if status == "deferred" and wait_reason == "spec-superseded":
            # tkt-237 M2 recovery: a prior run stamped this binder on disk
            # but its `git commit` failed mid-loop, leaving the stamp
            # uncommitted. The idempotent skip would strand it forever (bash
            # commits nothing on re-run). Detect the uncommitted mutation
            # (differs from HEAD) and emit it for bash to commit, recovering
            # the interrupted sweep without manual `git add -A && commit`.
            rel = os.path.relpath(binder, repo_root)
            diff_rc = subprocess.run(
                ["git", "-C", repo_root, "diff", "--quiet", "HEAD", "--", rel],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ).returncode
            if diff_rc == 0:
                report.append((n, status, "skip", "already stamped (idempotent)"))
                continue
            mutated.append(rel)
            report.append((n, status, "stamped",
                           "re-committed on-disk-stamped-but-uncommitted binder "
                           "(prior sweep commit failed mid-loop — M2 recovery)"))
            continue

        if status not in STAMPABLE:
            report.append((n, status or "(none)", "skip",
                            "terminal / side-state / pr-open / legacy" if status else "no status row"))
            continue

        if dry_run:
            report.append((n, status, "would-stamp", "deferred + spec-superseded"))
            continue

        # --- Contained read-modify-write mutations (under the lock) --------
        orig = s
        # 1. Flip status -> deferred (preserve the row shape: [ \t] not \s so the
        #    regex cannot swallow the trailing newline / merge the table). Group 2
        #    is the bare value-column-closing pipe (trailing [ \t]* eats whitespace
        #    before it) so the replacement yields `| status | deferred |` cleanly.
        s = re.sub(r'^(\|\s*status\s*\|)[ \t]*[^|]*?[ \t]*(\|)',
                   r'\1 deferred \2', s, count=1, flags=re.MULTILINE)

        # 2. Set wait_reason -> spec-superseded. Update the value column in place
        #    when the row exists (preserving any description column); insert a new
        #    row after the status row when absent.
        wr_row = re.compile(r'^(\|\s*wait_reason\s*\|)[ \t]*[^|]*?[ \t]*(\|)',
                            re.MULTILINE)
        if wr_row.search(s):
            s = wr_row.sub(r'\1 spec-superseded \2', s, count=1)
        else:
            # Insert after the status row, mirroring its column count so the table
            # stays well-formed. A 3-col status row (4 pipes) gets a 3-col insert;
            # a 2-col row gets a 2-col insert.
            status_row = re.search(r'^(\|\s*status\s*\|[ \t]*[^|]*?[ \t]*\|[ \t]*[^\n]*)\n',
                                   s, re.MULTILINE)
            if status_row:
                row = status_row.group(1)
                pipe_count = row.count("|")
                if pipe_count >= 4:
                    new_row = "| wait_reason | spec-superseded | (spec superseded) |"
                else:
                    new_row = "| wait_reason | spec-superseded |"
                s = s[:status_row.end()] + new_row + "\n" + s[status_row.end():]
            # else: no status row — the status flip above already failed silently;
            # the no-change guard below refuses the write.

        # 3. Journal entry under ## Decision journal.
        entry = (f"- spec {superseded_by} supersedes this ticket's Spec — "
                 f"stamp deferred + spec-superseded (supersede sweep {stamp})")
        m_hdr = re.search(r'^## Decision journal[ \t]*\n', s, re.MULTILINE)
        if m_hdr:
            body_start = m_hdr.end()
            tail = s[body_start:]
            bnd = re.search(r'\n## ', tail)
            if bnd:
                body, trailing = tail[:bnd.start()], tail[bnd.start():]
            else:
                body, trailing = tail, ""
            stripped = body.strip("\n")
            new_body = (stripped + "\n" + entry + "\n") if stripped else (entry + "\n")
            s = s[:body_start] + "\n" + new_body + trailing

        # 4. Bump `updated` atomically with the status flip (spc-186 A4).
        s = binder_rows.stamp_updated(s, stamp)

        if s == orig:
            report.append((n, status, "skip", "no mutation (status row missing?)"))
            continue

        # Atomic replace: temp + fsync + rename (the dir lock is already held).
        mode = os.stat(binder).st_mode
        fd, tmp = tempfile.mkstemp(dir=binder_dir, prefix=".supersede.", suffix=".tmp")
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

        rel = os.path.relpath(binder, repo_root)
        mutated.append(rel)
        report.append((n, "deferred", "stamped", "deferred + spec-superseded"))
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally:
            os.close(lock_fd)

# --- Report + emit mutated paths for bash to commit ------------------------
print("spec-supersede: sweep report", file=sys.stderr)
for n, st, action, detail in report:
    print(f"  tkt-{n}: {st} -> {action} ({detail})", file=sys.stderr)
print(f"spec-supersede: {len(mutated)} binder(s) stamped", file=sys.stderr)
print("SS_STATUS=ok")
for rel in mutated:
    print(rel)
PY
)
SS_RC=$?
if [[ $SS_RC -ne 0 ]]; then
  exit $SS_RC
fi

# --- Commit each mutated binder atomically (ratify.sh pattern) -------------
# Parse the sweep output: the SS_STATUS marker line, then one binder path
# per line. Commit each binder in its own commit so a crash between binders
# never leaves a half-written transaction.
MUTATED=$(printf '%s\n' "$SWEEP_OUT" | sed -n '/^SS_STATUS=/,$p' | tail -n +2)

if [[ "$DRY_RUN" == "true" ]]; then
  echo "spec-supersede: dry-run — no commits written"
  exit 0
fi

if [[ -z "$MUTATED" ]]; then
  echo "spec-supersede: no binders mutated (all skipped or idempotent)"
  exit 0
fi

COUNT=0
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  BINDER_NAME=$(basename "$(dirname "$rel")")
  git -C "$REPO_ROOT" add -- "$rel"
  git -C "$REPO_ROOT" commit -q \
    -m "supersede(${BINDER_NAME}): spec superseded — stamp deferred + spec-superseded" \
    -- "$rel"
  COUNT=$((COUNT + 1))
done <<<"$MUTATED"

echo "spec-supersede: done — ${COUNT} commit(s) written (one per stamped binder)"
