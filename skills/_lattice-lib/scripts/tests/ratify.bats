#!/usr/bin/env bats
# Tests for ratify.sh — single-commit ratification of a parked binder decision.
# Covers: canonical success + pending settlement, fail-safe rerun, journal at
# EOF and before another section, and the A2 preconditions (non-parked,
# missing-journal, untracked, out-of-home, symlinked, unrelated-staged).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export RF="$REPO_ROOT/skills/_lattice-lib/scripts/ratify.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ratify.XXXXXX")"
  REPO="$TEST_DIR/repo"
  BINDER_DIR="$REPO/.lattice/tickets/tkt-7-demo"
  mkdir -p "$BINDER_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  BINDER="$BINDER_DIR/README.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Canonical parked binder: journal before another section, one pending decision.
write_parked_binder() {
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| Field | Value |
| --- | --- |
| status | parked |

## Decision journal

## Pending decisions

- retry-lib vs backoff-lib — disposition: agent-decides

## Notes
MD
}

# Journal is the last section (at EOF), no pending decisions.
write_eof_journal_binder() {
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| Field | Value |
| --- | --- |
| status | parked |

## Decision journal
MD
}

@test "A1: canonical parked binder ratifies, records one dated decision, settles pending, flips to queued" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  run bash "$RF" --binder "$BINDER" \
    --decision "use retry-lib not backoff-lib (source: preference retry-at-most-once)" \
    --pending "retry-lib vs backoff-lib"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "single commit written"
  # status flipped parked → queued
  grep -qE '\| status \| queued \|' "$BINDER"
  # exactly one dated decision entry recorded
  [ "$(grep -Ec '^[-*] .*ratified 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$BINDER")" -eq 1 ]
  grep -q "use retry-lib not backoff-lib" "$BINDER"
  # pending decision settled (removed)
  if grep -q "retry-lib vs backoff-lib — disposition" "$BINDER"; then false; fi
  # ## Decision journal header appears exactly once
  [ "$(grep -c '^## Decision journal$' "$BINDER")" -eq 1 ]
  [ "$(grep -c '^## Pending decisions$' "$BINDER")" -eq 1 ]
}

@test "A4: updated row is bumped atomically with the parked → queued flip (tkt-191)" {
  write_parked_binder
  # add created/updated rows (template convention)
  sed -i.bak 's/| status | parked |/| status | parked |\n| created | 2026-01-01T00:00:00Z |\n| updated | 2026-01-01T00:00:00Z |/' "$BINDER"
  rm -f "$BINDER.bak"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  run bash "$RF" --binder "$BINDER" \
    --decision "use retry-lib not backoff-lib (source: preference retry-at-most-once)" \
    --pending "retry-lib vs backoff-lib"
  [ "$status" -eq 0 ]
  grep -qE '\| status \| queued \|' "$BINDER"
  # updated bumped to a real ISO-8601 UTC seconds-precision stamp
  grep -qE '\| updated \| 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \|' "$BINDER"
  # old value gone (bumped, not duplicated)
  if grep -q '| updated | 2026-01-01T00:00:00Z |' "$BINDER"; then false; fi
  # created is never bumped
  grep -q '| created | 2026-01-01T00:00:00Z |' "$BINDER"
}

@test "A1: one commit containing only the binder" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  printf 'unrelated\n' >"$REPO/notes.md"
  git -C "$REPO" add notes.md && git -C "$REPO" commit -qm base
  before=$(git -C "$REPO" rev-parse HEAD)
  run bash "$RF" --binder "$BINDER" --decision "pick foo" --pending "retry-lib vs backoff-lib"
  [ "$status" -eq 0 ]
  after=$(git -C "$REPO" rev-parse HEAD)
  [ "$before" != "$after" ]
  # exactly one new commit
  [ "$(git -C "$REPO" rev-list --count "$before..$after")" -eq 1 ]
  # the commit touches only the binder path
  changed=$(git -C "$REPO" show --name-only --oneline "$after" | tail -n +2)
  printf '%s\n' "$changed" | grep -qF "tkt-7-demo/README.md"
  [ -z "$(printf '%s\n' "$changed" | grep -F "notes.md")" ]
}

@test "A3: journal at EOF ratifies and appends the entry" {
  write_eof_journal_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  run bash "$RF" --binder "$BINDER" --decision "decide at EOF"
  [ "$status" -eq 0 ]
  grep -qE '\| status \| queued \|' "$BINDER"
  grep -q "decide at EOF (ratified 20" "$BINDER"
  [ "$(grep -c '^## Decision journal$' "$BINDER")" -eq 1 ]
}

@test "A3: rerun is fail-safe — second run does not mutate and does not duplicate" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  bash "$RF" --binder "$BINDER" --decision "pick foo" --pending "retry-lib vs backoff-lib" >/dev/null
  entry_count_first=$(grep -c 'pick foo' "$BINDER")
  [ "$entry_count_first" -eq 1 ]
  before=$(git -C "$REPO" rev-parse HEAD)
  run bash "$RF" --binder "$BINDER" --decision "pick foo"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "status is 'queued'"
  printf '%s\n' "$output" | grep -qF "expected 'parked'"
  after=$(git -C "$REPO" rev-parse HEAD)
  # no new commit
  [ "$before" = "$after" ]
  # no duplicate entry
  [ "$(grep -c 'pick foo' "$BINDER")" -eq 1 ]
}

@test "A2: non-parked binder is refused before mutation" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  sed -i.bak 's#| status | parked |#| status | queued |#' "$BINDER"
  rm -f "$BINDER.bak"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm flip
  before=$(git -C "$REPO" rev-parse HEAD)
  run bash "$RF" --binder "$BINDER" --decision "nope"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "status is 'queued'"
  after=$(git -C "$REPO" rev-parse HEAD)
  [ "$before" = "$after" ]
  grep -qE '\| status \| queued \|' "$BINDER"
  if grep -q "nope" "$BINDER"; then false; fi
}

@test "A2: missing ## Decision journal section is refused before mutation" {
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| Field | Value |
| --- | --- |
| status | parked |

## Notes
MD
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  before=$(git -C "$REPO" rev-parse HEAD)
  run bash "$RF" --binder "$BINDER" --decision "x"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "no "'`## Decision journal`'" section"
  after=$(git -C "$REPO" rev-parse HEAD)
  [ "$before" = "$after" ]
}

@test "A2: untracked binder is refused before mutation" {
  write_parked_binder
  # do NOT git add the binder — leave it untracked
  git -C "$REPO" add -A >/dev/null && git -C "$REPO" commit -qm base >/dev/null
  git -C "$REPO" rm -q --cached "$BINDER" 2>/dev/null || true
  run bash "$RF" --binder "$BINDER" --decision "x"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "not tracked by git"
}

@test "A2: out-of-home binder (outside .lattice/tickets) is refused" {
  outside="$REPO/README.md"
  printf '# repo readme\n\n| status | parked |\n\n## Decision journal\n' >"$outside"
  git -C "$REPO" add README.md && git -C "$REPO" commit -qm readme
  run bash "$RF" --binder "$outside" --decision "x"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must live under"
  [ "$(cat "$outside")" = "$(printf '# repo readme\n\n| status | parked |\n\n## Decision journal\n')" ]
}

@test "A2: symlinked binder pointing outside .lattice is refused" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  secret="$TEST_DIR/secret.txt"
  printf 'do not touch\n' >"$secret"
  ln -sf "$secret" "$BINDER_DIR/link.md"
  run bash "$RF" --binder "$BINDER_DIR/link.md" --decision "x"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "symlinked binder path component"
  [ "$(cat "$secret")" = "do not touch" ]
}

@test "A2: unrelated pre-staged file is refused before mutation" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  # stage an unrelated file alongside the binder
  printf 'junk\n' >"$REPO/junk.txt"
  git -C "$REPO" add junk.txt
  before=$(git -C "$REPO" rev-parse HEAD)
  run bash "$RF" --binder "$BINDER" --decision "x"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "unrelated pre-staged path"
  after=$(git -C "$REPO" rev-parse HEAD)
  [ "$before" = "$after" ]
  if grep -q "ratified" "$BINDER"; then false; fi
  # the staged junk remains staged but is NOT committed
  git -C "$REPO" diff --cached --name-only | grep -q 'junk.txt'
}

@test "A2: binder itself pre-staged is allowed (re-staged and committed)" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  # pre-stage the binder (e.g. a prior tweak) — this is not 'unrelated'
  git -C "$REPO" add "$BINDER"
  run bash "$RF" --binder "$BINDER" --decision "ok" --pending "retry-lib vs backoff-lib"
  [ "$status" -eq 0 ]
  grep -qE '\| status \| queued \|' "$BINDER"
}

@test "A2: malformed binder (no status row) is refused" {
  cat >"$BINDER" <<'MD'
# tkt-7-demo

## Decision journal
MD
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  run bash "$RF" --binder "$BINDER" --decision "x"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "no \`| status | … |\` field row"
}

@test "A1: --pending with zero matches is refused before mutation" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  run bash "$RF" --binder "$BINDER" --decision "x" --pending "no-such-decision"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "matched no pending decision bullet"
  if grep -q "ratified" "$BINDER"; then false; fi
  grep -qE '\| status \| parked \|' "$BINDER"
}

@test "A1: --pending with multiple matches is refused (ambiguous)" {
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| Field | Value |
| --- | --- |
| status | parked |

## Decision journal

## Pending decisions

- alpha dup
- beta dup

## Notes
MD
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  run bash "$RF" --binder "$BINDER" --decision "x" --pending "dup"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "matched 2 pending decision bullets"
}

@test "A1: omitting --pending leaves the pending section untouched" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  run bash "$RF" --binder "$BINDER" --decision "pick foo"
  [ "$status" -eq 0 ]
  grep -q "retry-lib vs backoff-lib — disposition: agent-decides" "$BINDER"
  grep -qE '\| status \| queued \|' "$BINDER"
}

@test "binder keeps its mode and leaves no temp/lock residue after atomic rewrite" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  chmod 640 "$BINDER"
  run bash "$RF" --binder "$BINDER" --decision "pick foo" --pending "retry-lib vs backoff-lib"
  [ "$status" -eq 0 ]
  perms=$(ls -l "$BINDER" | cut -c1-10)
  [ "$perms" = "-rw-r-----" ]
  run bash -c "ls -A '$BINDER_DIR' | grep -cE '\.(lock|tmp)\$' || true"
  [ "$output" = "0" ]
}

@test "usage: missing --binder and missing --decision exit 2" {
  run bash "$RF"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--binder required"
  run bash "$RF" --binder "$BINDER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--decision required"
}

@test "usage: unknown argument exits 2" {
  run bash "$RF" --binder "$BINDER" --decision "x" --bogus
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "unknown arg: --bogus"
}

@test "A2: multi-line --decision is rejected (no embedded newlines)" {
  write_parked_binder
  git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  # Embed a literal newline in --decision via $'…'
  run bash "$RF" --binder "$BINDER" --decision $'line one\nline two'
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "single line (no embedded newlines)"
  # binder untouched
  grep -qE '\| status \| parked \|' "$BINDER"
  if grep -q "line one" "$BINDER"; then false; fi
}
