#!/usr/bin/env bats
# Tests for next-artifact-id.sh (spc local claim + rev R1)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export NEXT_ID="$REPO_ROOT/skills/_lattice-lib/scripts/next-artifact-id.sh"
}

setup() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/lattice-ids.XXXXXX")"
  mkdir -p "$TEST_HOME/specs" "$TEST_HOME/reviews"
  # Run outside any git repo: with a git ROOT the script also scans
  # <root>/docs/design, which would leak this monorepo's rev files in.
  cd "$TEST_HOME"
}

teardown() {
  cd /
  rm -rf "$TEST_HOME"
}

# ---- Spec (local monotonic — not team SoT) ----

# Helper: spc path prints team-SoT warning on stderr; some bats hosts merge streams.
spc_out() {
  bash "$NEXT_ID" --kind spc --home "$TEST_HOME" "$@" 2>/dev/null
}

@test "scan-only returns max+1 from existing files" {
  touch "$TEST_HOME/specs/spc-3-foo.md"
  run spc_out
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "empty home starts at 1 for spc" {
  run spc_out
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "zero-padded legacy names normalize" {
  touch "$TEST_HOME/specs/spc-007-legacy.md"
  run spc_out
  [ "$status" -eq 0 ]
  [ "$output" = "8" ]
}

@test "claim reserves the id so the next claim advances" {
  touch "$TEST_HOME/specs/spc-2-foo.md"
  run spc_out --claim
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
  [ -d "$TEST_HOME/.ids/spc-3" ]
  run spc_out --claim
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "spc parallel claims never hand out duplicates" {
  local out="$TEST_HOME/parallel.out"
  for _ in 1 2 3 4 5 6 7 8; do
    bash "$NEXT_ID" --kind spc --home "$TEST_HOME" --claim 2>/dev/null >>"$out" &
  done
  wait
  run sort -n "$out"
  [ "$status" -eq 0 ]
  dupes=$(sort -n "$out" | uniq -d)
  [ -z "$dupes" ]
  [ "$(wc -l < "$out")" -eq 8 ]
}

@test "spc emits team-SoT warning on stderr" {
  run bash "$NEXT_ID" --kind spc --home "$TEST_HOME"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"NOT team SoT"* ]] || [[ "$output" == *"NOT team SoT"* ]] || {
    # bats may merge streams depending on version — check full run output via re-run
    run bash -c "bash \"$NEXT_ID\" --kind spc --home \"$TEST_HOME\" 2>&1 >/dev/null"
    printf '%s\n' "$output" | grep -qF "NOT team SoT"
  }
}

# ---- Review R1 ----

@test "rev allocates R1 UTC token matching YYYYMMDD-HHMMSSZ" {
  run bash "$NEXT_ID" --kind rev --home "$TEST_HOME" --claim
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^[0-9]{8}-[0-9]{6}Z(-[a-z0-9]+)?$'
  [ -d "$TEST_HOME/.ids/rev-${output}" ]
}

@test "rev claim collision gets unique suffix" {
  # Pre-create claim for "current" second is hard; force collision by claiming twice
  # in the same second — second should differ or equal only if mkdir races resolved.
  t1=$(bash "$NEXT_ID" --kind rev --home "$TEST_HOME" --claim 2>/dev/null)
  t2=$(bash "$NEXT_ID" --kind rev --home "$TEST_HOME" --claim 2>/dev/null)
  [ -n "$t1" ]
  [ -n "$t2" ]
  [ "$t1" != "$t2" ]
}

@test "rev respects existing review file path" {
  tok=$(date -u +%Y%m%d-%H%M%SZ)
  touch "$TEST_HOME/reviews/rev-${tok}-taken.md"
  run bash "$NEXT_ID" --kind rev --home "$TEST_HOME" --claim
  [ "$status" -eq 0 ]
  [ "$output" != "$tok" ]
  printf '%s\n' "$output" | grep -qE '^[0-9]{8}-[0-9]{6}Z(-[a-z0-9]+)?$'
}

@test "invalid kind is rejected" {
  run bash "$NEXT_ID" --kind tkt --home "$TEST_HOME"
  [ "$status" -eq 2 ]
}

@test "from sibling worktree: rev claim lands on MAIN .ids" {
  git init -q -b main "$TEST_HOME/repo"
  git -C "$TEST_HOME/repo" config user.email lattice-test@example.invalid
  git -C "$TEST_HOME/repo" config user.name 'Lattice Test'
  git -C "$TEST_HOME/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p "$TEST_HOME/repo/.lattice/reviews"
  git -C "$TEST_HOME/repo" worktree add -q "$TEST_HOME/repo.worktrees/tkt-1-x" -b tkt-1-x
  cd "$TEST_HOME/repo.worktrees/tkt-1-x"
  unset LATTICE_HOME
  run bash "$NEXT_ID" --kind rev --claim
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^[0-9]{8}-[0-9]{6}Z(-[a-z0-9]+)?$'
  [ -d "$TEST_HOME/repo/.lattice/.ids/rev-${output}" ]
}

@test "tkt-463: rev claim collision terminates even when SIGPIPE is ignored (macOS BSD tr hang regression)" {
  # GitHub's macOS runner executes bats with SIGPIPE ignored; the old
  # `tr -dc … </dev/urandom | head -c 3` producer then never exits on BSD tr.
  # Bounded watchdog (portable bash — no `timeout` on macOS): the two claims
  # must finish within 20s or the test fails instead of hanging the job.
  bash -c 'trap "" PIPE; "$0" --kind rev --home "$1" --claim >/dev/null 2>&1; "$0" --kind rev --home "$1" --claim >/dev/null 2>&1' "$NEXT_ID" "$TEST_HOME" &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 20 ]; then kill "$pid" 2>/dev/null; pkill -P "$pid" 2>/dev/null; false; fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid"
  [ "$(ls -1 "$TEST_HOME/.ids" | grep -c '^rev-')" -ge 2 ]
}
