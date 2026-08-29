#!/usr/bin/env bats
# verify-mutation.bats — confirm the verify-after-mutate helper.
# tkt-167 ergonomics: run + [ "$status" ... ]; [ ! -f ] / [ -f ]. No bare !/[[ ]].

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
export REPO_ROOT
SCRIPT="$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh"

setup_fake_gh() {
  FAKE_GH_DIR="$BATS_TMPDIR/vm-fake-gh-${BATS_TEST_NUMBER:-0}-$$"
  mkdir -p "$FAKE_GH_DIR/bin"
  PR_STATE="$1"; PR_HEAD="$2"; PR_URL="${3:-https://github.com/percena/lattice/pull/1}"
  printf '#!/usr/bin/env bash\n' > "$FAKE_GH_DIR/bin/gh"
  if [ "$PR_STATE" = "MERGED" ]; then
    printf 'case "$3" in 1) printf '"'"'{"state":"MERGED","headRefOid":"%s","url":"%s"}'"'"';;2) printf '"'"'{"state":"CLOSED","headRefOid":"abc1234","url":"https://github.com/percena/lattice/pull/2"}'"'"';;3) exit 1;;*) exit 1;;esac\n' "$PR_HEAD" "$PR_URL" >> "$FAKE_GH_DIR/bin/gh"
  else
    printf 'case "$3" in 1) printf '"'"'{"state":"OPEN","headRefOid":"%s","url":"%s"}'"'"';;2) printf '"'"'{"state":"CLOSED","headRefOid":"abc1234","url":"https://github.com/percena/lattice/pull/2"}'"'"';;3) exit 1;;*) exit 1;;esac\n' "$PR_HEAD" "$PR_URL" >> "$FAKE_GH_DIR/bin/gh"
  fi
  chmod +x "$FAKE_GH_DIR/bin/gh"
  export PATH="$FAKE_GH_DIR/bin:$PATH"
}

teardown() {
  [ -n "${FAKE_GH_DIR:-}" ] && rm -rf "$FAKE_GH_DIR" 2>/dev/null || true
}

@test "usage: no args exits 2" {
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh"
  [ "$status" -eq 2 ]
}

@test "usage: --help exits 0" {
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --help
  [ "$status" -eq 0 ]
}

@test "usage: two kinds rejected (exit 2)" {
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 1 --commit abc1234
  [ "$status" -eq 2 ]
}

@test "pr: existing OPEN PR verifies (exit 0)" {
  setup_fake_gh "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verified: pr-1 OPEN head=abc1234abcd'
}

@test "pr: nonexistent PR fails (exit 1, never silent)" {
  setup_fake_gh "OPEN" "abc1234abcd"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 3
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED'
}

@test "pr: CLOSED PR fails without --allow-merged (exit 1)" {
  setup_fake_gh "CLOSED" "abc1234"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 2
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'CLOSED'
}

@test "pr: --allow-merged accepts MERGED" {
  setup_fake_gh "MERGED" "abc1234"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 1 --allow-merged
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verified: pr-1 MERGED'
}

@test "pr: --expected-oid mismatch fails (exit 1)" {
  setup_fake_gh "OPEN" "abc1234abcd"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 1 --expected-oid deadbeef
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '!='
}

@test "pr: --expected-oid match verifies" {
  setup_fake_gh "OPEN" "abc1234abcd"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 1 --expected-oid abc1234abcd
  [ "$status" -eq 0 ]
}

@test "pr: --repo identity mismatch fails" {
  setup_fake_gh "OPEN" "abc1234abcd" "https://github.com/other/repo/pull/1"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 1 --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'different repo'
}

@test "pr: --repo identity match verifies" {
  setup_fake_gh "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr 1 --repo percena/lattice
  [ "$status" -eq 0 ]
}

@test "pr: non-numeric pr fails (exit 2)" {
  setup_fake_gh "OPEN" "abc1234abcd"
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --pr abc
  [ "$status" -eq 1 ]
}

@test "commit: existing object verifies" {
  OID=$(git -C "$REPO_ROOT" rev-parse HEAD)
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --commit "$OID"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verified: commit'
}

@test "commit: nonexistent object fails (exit 1, never silent)" {
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --commit deadbee
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED'
}

@test "commit: non-hex oid rejected (exit 1)" {
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --commit notahex
  [ "$status" -eq 1 ]
}

@test "branch: nonexistent remote branch fails" {
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh" --branch nonexistent-branch-xyz
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED'
}
