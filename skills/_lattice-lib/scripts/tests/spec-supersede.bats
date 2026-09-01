#!/usr/bin/env bats
# Tests for spec-supersede.sh — trip-time sweep of a superseded Spec's child
# binders (spc-186 A3 / tkt-190). Covers: canonical sweep stamps
# queued/in-progress/deferred, skips terminal + side-states + pr-open;
# idempotent re-run; dry-run; preconditions (non-superseded, unset
# superseded_by, no tickets); wait_reason row update vs insert; single-commit
# per binder; unrelated-staged refusal.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export SS="$REPO_ROOT/skills/_lattice-lib/scripts/spec-supersede.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/supersede.XXXXXX")"
  REPO="$TEST_DIR/repo"
  # tkt-299: route ledger writes to the tmp repo home (no tkt-10/11/12.jsonl
  # residue); spec-supersede also derives HOME_DIR from the spec path, but the
  # export makes the bash commit/record subprocess consistent.
  export LATTICE_HOME="$REPO/.lattice"
  SPECS_DIR="$REPO/.lattice/specs"
  mkdir -p "$SPECS_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Write a superseded spec whose tickets list is the given bare ids.
# Args: ticket_nums ("10,11,12")  — written as tkt-N (spec front-matter canon)
write_spec() {
  local nums="${1:-}"
  local ids=""
  if [[ -n "$nums" ]]; then
    local IFS=','
    for n in $nums; do
      [[ -z "$ids" ]] && ids="tkt-${n}" || ids="${ids}, tkt-${n}"
    done
  fi
  cat >"$SPECS_DIR/spc-5-old.md" <<MD
---
id: spc-5
slug: old
status: superseded
supersedes: []
superseded_by: spc-9
tickets: [${ids}]
---
# spc-5
MD
}

# Write a binder at .lattice/tickets/tkt-N-<slug>/README.md.
# Args: n slug status [extra_table_rows]
write_binder() {
  local n="$1" slug="$2" status="$3" extra="${4:-}"
  local dir="$REPO/.lattice/tickets/tkt-${n}-${slug}"
  mkdir -p "$dir"
  {
    echo "# tkt-${n}-${slug}"
    echo ""
    echo "| Field | Value |"
    echo "| --- | --- |"
    echo "| status | ${status} |"
    if [[ -n "$extra" ]]; then
      printf '%s\n' "$extra"
    fi
    echo "| updated | 2026-08-20T00:00:00Z |"
    echo ""
    echo "## Decision journal"
  } >"$dir/README.md"
}

commit_all() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm init
}

@test "A3: sweep stamps queued + in-progress + deferred, skips closed/pr-open/parked/stuck/rework/open" {
  write_spec "10,11,12,13,14,15,16,17"
  # stampable
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  write_binder 11 wip "in-progress" "| wait_reason | (none) |"
  write_binder 12 held "deferred" "| wait_reason | fuse-halt |"
  # skipped: terminal + side-states + pr-open + legacy
  write_binder 13 done "closed" "| wait_reason | (none) |"
  write_binder 14 parked "parked" "| wait_reason | unblock |"
  write_binder 15 stuck "stuck" "| wait_reason | re-scope |"
  write_binder 16 rework "rework" "| wait_reason | (none) |"
  write_binder 17 openpr "pr-open" "| wait_reason | (none) |"
  commit_all

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "3 binder(s) stamped"
  # stampable three -> deferred + spec-superseded
  grep -qE '\| status \| deferred \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
  grep -qE '\| wait_reason \| spec-superseded \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
  grep -qE '\| status \| deferred \|' "$REPO/.lattice/tickets/tkt-11-wip/README.md"
  grep -qE '\| wait_reason \| spec-superseded \|' "$REPO/.lattice/tickets/tkt-11-wip/README.md"
  # already-deferred re-stamped to spec-superseded (prior fuse-halt overwritten)
  grep -qE '\| wait_reason \| spec-superseded \|' "$REPO/.lattice/tickets/tkt-12-held/README.md"
  # skipped binders untouched (status unchanged)
  grep -qE '\| status \| closed \|' "$REPO/.lattice/tickets/tkt-13-done/README.md"
  grep -qE '\| status \| parked \|' "$REPO/.lattice/tickets/tkt-14-parked/README.md"
  grep -qE '\| status \| stuck \|' "$REPO/.lattice/tickets/tkt-15-stuck/README.md"
  grep -qE '\| status \| rework \|' "$REPO/.lattice/tickets/tkt-16-rework/README.md"
  grep -qE '\| status \| pr-open \|' "$REPO/.lattice/tickets/tkt-17-openpr/README.md"
  # skipped binders kept their original wait_reason
  grep -qE '\| wait_reason \| unblock \|' "$REPO/.lattice/tickets/tkt-14-parked/README.md"
  grep -qE '\| wait_reason \| re-scope \|' "$REPO/.lattice/tickets/tkt-15-stuck/README.md"
  # journal entry recorded on a stamped binder
  grep -qE '^- spec spc-9 supersedes' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
  grep -qE 'stamp deferred \+ spec-superseded' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
  # updated stamp bumped past the original 2026-08-20 baseline
  grep -qE '\| updated \| 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]+Z \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
  if grep -qE '\| updated \| 2026-08-20T00:00:00Z \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"; then false; fi
}

@test "A3: wait_reason row inserted when absent (in-progress binder, 2-col table)" {
  write_spec "11"
  write_binder 11 wip "in-progress"
  commit_all

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  # inserted wait_reason row appears right after the status row
  grep -qE '^\| status \| deferred \|$' "$REPO/.lattice/tickets/tkt-11-wip/README.md"
  grep -qE '^\| wait_reason \| spec-superseded \|$' "$REPO/.lattice/tickets/tkt-11-wip/README.md"
}

@test "A3: sweep is idempotent — re-run stamps nothing" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  commit_all

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  local commits_after_first
  commits_after_first=$(git -C "$REPO" rev-list --count HEAD)
  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "no binders mutated"
  local commits_after_second
  commits_after_second=$(git -C "$REPO" rev-list --count HEAD)
  # no new commit on the idempotent re-run
  [ "$commits_after_first" -eq "$commits_after_second" ]
}

@test "A3: each stamped binder is its own single commit (ratify.sh pattern)" {
  write_spec "10,11"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  write_binder 11 wip "in-progress" "| wait_reason | (none) |"
  commit_all

  local before
  before=$(git -C "$REPO" rev-list --count HEAD)
  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  local after
  after=$(git -C "$REPO" rev-list --count HEAD)
  # exactly two new commits (one per binder)
  [ $((after - before)) -eq 2 ]
  git -C "$REPO" log --oneline | grep -qE 'supersede\(tkt-10-queued\)'
  git -C "$REPO" log --oneline | grep -qE 'supersede\(tkt-11-wip\)'
  # each commit touched exactly one binder file
  local latest
  latest=$(git -C "$REPO" rev-parse HEAD)
  [ "$(git -C "$REPO" show --name-only --format='' "$latest" | grep -cE 'README.md')" -eq 1 ]
}

@test "dry-run reports the plan and writes no commits" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  commit_all

  local before
  before=$(git -C "$REPO" rev-list --count HEAD)
  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md" --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "would-stamp"
  printf '%s\n' "$output" | grep -qF "dry-run"
  local after
  after=$(git -C "$REPO" rev-list --count HEAD)
  [ "$before" -eq "$after" ]
  # binder untouched in dry-run
  grep -qE '\| status \| queued \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
}

@test "precondition: non-superseded spec refuses" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  # Flip the spec status to locked (not yet superseded)
  cat >"$SPECS_DIR/spc-5-old.md" <<'MD'
---
id: spc-5
slug: old
status: locked
supersedes: []
superseded_by: spc-9
tickets: [tkt-10]
---
# spc-5
MD
  commit_all

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "expected 'superseded'"
  # binder untouched
  grep -qE '\| status \| queued \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
}

@test "precondition: superseded_by unset refuses" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  # superseded but superseded_by is null
  cat >"$SPECS_DIR/spc-5-old.md" <<'MD'
---
id: spc-5
slug: old
status: superseded
supersedes: []
superseded_by: null
tickets: [tkt-10]
---
# spc-5
MD
  commit_all

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "superseded_by is unset"
  grep -qE '\| status \| queued \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
}

@test "precondition: spec with no child tickets is a no-op" {
  write_spec ""
  commit_all

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "nothing to sweep"
}

@test "precondition: spec not tracked by git refuses" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  # commit only the binder, leave the spec untracked
  git -C "$REPO" add .lattice/tickets
  git -C "$REPO" commit -qm binders

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "not tracked by git"
}

@test "unrelated pre-staged path refuses before any mutation" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  commit_all
  # stage an unrelated file
  echo "junk" >"$REPO/unrelated.txt"
  git -C "$REPO" add unrelated.txt

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "unrelated pre-staged"
  # binder untouched
  grep -qE '\| status \| queued \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
}

@test "missing binder for a declared ticket is reported and skipped" {
  write_spec "10,11"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  # tkt-11 has no binder directory
  commit_all

  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "1 binder(s) stamped"
  printf '%s\n' "$output" | grep -qE "tkt-11.*no binder found"
  grep -qE '\| status \| deferred \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
}

# ---------------------------------------------------------------------------
# tkt-237 M1: read-before-lock TOCTOU. The dir lock must guard the WHOLE
# read-modify-write (lock BEFORE read), so a concurrent stamp (queued ->
# pr-open + prs entry) in the read->replace window is not lost on overwrite.
# Deterministic: a locker holds LOCK_EX, the sweep blocks on the lock, the
# locker stamps pr-open on disk while the sweep waits, then releases. The
# sweep must re-read under the lock (see pr-open) and skip — NOT overwrite
# the pr-open stamp with deferred computed from a stale queued read.
# ---------------------------------------------------------------------------

@test "M1 TOCTOU: concurrent stamp during sweep's lock-wait is not lost (re-read under lock)" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  commit_all

  BINDER_DIR10="$REPO/.lattice/tickets/tkt-10-queued"
  # Barrier files coordinate the race deterministically (heredoc bodies are
  # data; the flock calls below run in the background subshell, not as bats
  # assertions, so check-bats-assertions stays clean).
  (
    BBD="$BINDER_DIR10" python3 - "$BINDER_DIR10/README.md" <<'PY'
import fcntl, os, sys, time
binder = sys.argv[1]
d = os.path.dirname(binder) or "."
fd = os.open(d, os.O_RDONLY)
fcntl.flock(fd, fcntl.LOCK_EX)
# signal: the lock is held; the sweep may now start and block on it.
open(os.path.join(d, ".race-locked"), "w").close()
# wait for the sweep to be blocked on the lock (race-go sentinel).
for _ in range(200):
    if os.path.exists(os.path.join(d, ".race-go")):
        break
    time.sleep(0.01)
# concurrent stamp: flip queued -> pr-open on disk while the sweep waits.
import re
s = open(binder, encoding="utf-8").read()
s = re.sub(r'^(\|\s*status\s*\|)[ \t]*[^|]*?[ \t]*(\|)',
           r'\1 pr-open \2', s, count=1, flags=re.MULTILINE)
open(binder, "w", encoding="utf-8").write(s)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
  ) &
  LOCKER_PID=$!

  # wait until the locker holds the lock (deterministic barrier)
  for _ in $(seq 1 200); do
    [ -f "$BINDER_DIR10/.race-locked" ] && break
    sleep 0.01
  done
  # release the locker's sentinel so it stamps + releases the lock
  : >"$BINDER_DIR10/.race-go"
  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  wait $LOCKER_PID
  rm -f "$BINDER_DIR10/.race-locked" "$BINDER_DIR10/.race-go"

  [ "$status" -eq 0 ]
  # the concurrent pr-open stamp was NOT overwritten by a stale deferred stamp
  grep -qE '\| status \| pr-open \|' "$BINDER_DIR10/README.md"
  if grep -qE '\| status \| deferred \|' "$BINDER_DIR10/README.md"; then false; fi
  # the sweep read the fresh pr-open under the lock and skipped (not stampable)
  printf '%s\n' "$output" | grep -qE "tkt-10.*skip"
  printf '%s\n' "$output" | grep -qE "0 binder\(s\) stamped"
}

# ---------------------------------------------------------------------------
# tkt-237 M2: mutate-all-then-commit. A prior sweep stamped a binder on disk
# but its `git commit` failed mid-loop, leaving the stamp uncommitted. A
# re-run's idempotent skip would strand it (bash commits nothing). The
# recovery path detects the on-disk-stamped-but-uncommitted binder and emits
# it for bash to commit.
# ---------------------------------------------------------------------------

@test "M2 recovery: on-disk-stamped-but-uncommitted binder is committed on re-run" {
  write_spec "10"
  write_binder 10 queued "queued" "| wait_reason | (none) |"
  commit_all
  # Simulate a prior sweep that stamped the binder on disk but never committed
  # it (git commit failed mid-loop): flip the rows on disk, leave uncommitted.
  sed -i.bak 's/| status | queued |/| status | deferred |/; s/| wait_reason | (none) |/| wait_reason | spec-superseded |/' \
    "$REPO/.lattice/tickets/tkt-10-queued/README.md"
  rm -f "$REPO/.lattice/tickets/tkt-10-queued/README.md.bak"
  # the on-disk stamp IS uncommitted (differs from HEAD)
  if git -C "$REPO" diff --quiet HEAD -- .lattice/tickets/tkt-10-queued/README.md; then false; fi

  local before
  before=$(git -C "$REPO" rev-list --count HEAD)
  run bash "$SS" --spec "$SPECS_DIR/spc-5-old.md"
  [ "$status" -eq 0 ]
  local after
  after=$(git -C "$REPO" rev-list --count HEAD)
  # exactly one commit written (the recovered stamp), binder now committed
  [ $((after - before)) -eq 1 ]
  printf '%s\n' "$output" | grep -qE "re-committed"
  # the binder matches HEAD now (no longer uncommitted)
  git -C "$REPO" diff --quiet HEAD -- .lattice/tickets/tkt-10-queued/README.md
  # and the stamp is intact
  grep -qE '\| status \| deferred \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
  grep -qE '\| wait_reason \| spec-superseded \|' "$REPO/.lattice/tickets/tkt-10-queued/README.md"
}
