#!/usr/bin/env bats
# Tests for bump-fix-cycle.sh: scripted fix_cycles owner + pr-open → rework
# transition + cap-exit to deep-review (spc-186 A6/A8, ADR-007 five-piece).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export BFC="$REPO_ROOT/skills/_lattice-lib/scripts/bump-fix-cycle.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bfc.XXXXXX")"
  REPO="$TEST_DIR/repo"
  BINDER_DIR="$REPO/.lattice/tickets/tkt-9-demo"
  mkdir -p "$BINDER_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  BINDER="$BINDER_DIR/README.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_bfc() {
  run bash "$BFC" "$@"
}

write_binder() {
  # $1 = status, $2 = fix_cycles value (omit the row entirely if "none")
  local status="$1"
  local fc="$2"
  {
    cat <<MD
# tkt-9-demo

| Field | Value |
| --- | --- |
| github | https://github.com/acme/repo/issues/9 |
| status | $status |
MD
    if [[ "$fc" != "none" ]]; then
      printf '| fix_cycles | %s |\n' "$fc"
    fi
    cat <<'MD'
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** thing

## Decision journal

- 2026-08-29 — created.

## Notes

(none)
MD
  } >"$BINDER"
}

@test "normal bump: pr-open fix_cycles 0 → rework +1, journals cycle trace" {
  write_binder pr-open 0
  run_bfc --binder "$BINDER" --note "high correctness finding on retry path"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "stamped rework + fix_cycles 1"
  grep -q '| status | rework |' "$BINDER"
  grep -q '| fix_cycles | 1 |' "$BINDER"
  grep -q 'fix cycle 1: `pr-open` → rework' "$BINDER"
  grep -qF 'fix_cycles 1' "$BINDER"
  grep -qF 'high correctness finding on retry path' "$BINDER"
}

@test "second bump within cap: fix_cycles 1 → 2 (at cap, still OK)" {
  write_binder pr-open 1
  run_bfc --binder "$BINDER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "stamped rework + fix_cycles 2"
  grep -q '| status | rework |' "$BINDER"
  grep -q '| fix_cycles | 2 |' "$BINDER"
  grep -q 'fix cycle 2: `pr-open` → rework' "$BINDER"
}

@test "cap-hit: third rework (fix_cycles 2) holds at 2, forces deep-review, no auto-retry" {
  write_binder pr-open 2
  run_bfc --binder "$BINDER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "CAP-HIT"
  printf '%s\n' "$output" | grep -qF "fix_cycles holds at 2"
  printf '%s\n' "$output" | grep -qF "deep-review"
  printf '%s\n' "$output" | grep -qF -- "--extend-budget"
  # binder stays rework, fix_cycles holds at 2 (NOT 3)
  grep -q '| status | rework |' "$BINDER"
  grep -q '| fix_cycles | 2 |' "$BINDER"
  if grep -q '| fix_cycles | 3 |' "$BINDER"; then false; fi
  # structured trace in Decision journal
  grep -q 'CAP-HIT: fix_cycles at cap (2)' "$BINDER"
  grep -qF 'FORCED to `deep-review`' "$BINDER"
  grep -qF 'ADR-007 §4 five-piece' "$BINDER"
}

@test "cap-hit is idempotent: re-run on the rework cap-hit binder reprints CAP-HIT, mutates nothing" {
  write_binder pr-open 2
  run_bfc --binder "$BINDER"
  [ "$status" -eq 0 ]
  cp "$BINDER" "$TEST_DIR/binder-after-first.md"
  run_bfc --binder "$BINDER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "CAP-HIT"
  printf '%s\n' "$output" | grep -qF "already rework at cap"
  printf '%s\n' "$output" | grep -qF "deep-review"
  grep -q '| fix_cycles | 2 |' "$BINDER"
  if grep -q '| fix_cycles | 3 |' "$BINDER"; then false; fi
  cmp -s "$BINDER" "$TEST_DIR/binder-after-first.md"
  grep -q 'CAP-HIT: fix_cycles at cap (2)' "$BINDER"
}

@test "escape: --extend-budget --reason bumps past cap + journals operator-adjudicated trace" {
  write_binder pr-open 2
  run_bfc --binder "$BINDER" --extend-budget --reason "operator reviewed; one more cycle warranted"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ESCAPE"
  printf '%s\n' "$output" | grep -qF "fix_cycles bumped to 3"
  grep -q '| status | rework |' "$BINDER"
  grep -q '| fix_cycles | 3 |' "$BINDER"
  grep -q 'ESCAPE: fix_cycles bumped to 3' "$BINDER"
  grep -qF 'operator-adjudicated — ADR-007 §5b' "$BINDER"
  grep -qF 'operator reviewed; one more cycle warranted' "$BINDER"
}

@test "escape on an already-rework cap-hit binder bumps under --extend-budget" {
  write_binder rework 2
  run_bfc --binder "$BINDER" --extend-budget --reason "human adjudicates the cap-hit"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ESCAPE"
  grep -q '| status | rework |' "$BINDER"
  grep -q '| fix_cycles | 3 |' "$BINDER"
  grep -q 'ESCAPE: fix_cycles bumped to 3' "$BINDER"
}

@test "--extend-budget without --reason is a usage error" {
  write_binder pr-open 2
  run_bfc --binder "$BINDER" --extend-budget
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--extend-budget requires --reason"
  # binder untouched
  grep -q '| status | pr-open |' "$BINDER"
  grep -q '| fix_cycles | 2 |' "$BINDER"
}

@test "refuses rework binder without --extend-budget (must return to pr-open first)" {
  write_binder rework 1
  run_bfc --binder "$BINDER"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "REFUSED"
  printf '%s\n' "$output" | grep -qF "already `rework`"
  printf '%s\n' "$output" | grep -qF -- "--extend-budget"
  grep -q '| status | rework |' "$BINDER"
  grep -q '| fix_cycles | 1 |' "$BINDER"
}

@test "refuses non-pr-open / non-rework statuses (e.g. queued, in-progress)" {
  for st in queued in-progress parked stuck deferred; do
    write_binder "$st" 0
    run_bfc --binder "$BINDER"
    [ "$status" -eq 1 ]
    printf '%s\n' "$output" | grep -qF "REFUSED"
    printf '%s\n' "$output" | grep -qF "$st"
    grep -q -- "| status | $st |" "$BINDER"
  done
}

@test "refuses terminal (closed) binder" {
  write_binder closed 0
  run_bfc --binder "$BINDER"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "REFUSED"
  printf '%s\n' "$output" | grep -qF "terminal"
}

@test "lazy migration: missing fix_cycles row is created on first bump" {
  write_binder pr-open none
  run_bfc --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -q '| fix_cycles | 1 |' "$BINDER"
  grep -q '| status | rework |' "$BINDER"
  # row lands right after the status row (line numbers consecutive)
  status_line=$(grep -n '^| status | rework |' "$BINDER" | head -1 | cut -d: -f1)
  fc_line=$(grep -n '^| fix_cycles | 1 |' "$BINDER" | head -1 | cut -d: -f1)
  [ -n "$status_line" ]
  [ -n "$fc_line" ]
  [ "$((fc_line - status_line))" -eq 1 ]
}

@test "dry-run mutates nothing but reports the planned stamp" {
  write_binder pr-open 0
  cp "$BINDER" "$TEST_DIR/before.md"
  run_bfc --binder "$BINDER" --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "DRY-RUN"
  printf '%s\n' "$output" | grep -qF "fix_cycles 1"
  cmp -s "$BINDER" "$TEST_DIR/before.md"
}

@test "dry-run cap-hit reports without mutating" {
  write_binder pr-open 2
  cp "$BINDER" "$TEST_DIR/before.md"
  run_bfc --binder "$BINDER" --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "DRY-RUN"
  printf '%s\n' "$output" | grep -qF "CAP-HIT"
  cmp -s "$BINDER" "$TEST_DIR/before.md"
}

@test "no binder file: skip with note, exit 0 (ticket-only flow)" {
  run_bfc --binder "$BINDER_DIR/nonexistent.md"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "skip"
}

@test "refuses a binder path outside the repo .lattice/ tree" {
  OUT="$REPO/outside.md"
  printf '# outside\n\n| status | pr-open |\n' >"$OUT"
  run_bfc --binder "$OUT"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must live under"
}

@test "usage header documents the cap-exit and escape channel" {
  run_bfc --help
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "fix_cycles"
  printf '%s\n' "$output" | grep -qF -- "--extend-budget"
  printf '%s\n' "$output" | grep -qF "deep-review"
}

@test "symlinked entrypoint resolves back to trusted install, not a consumer fake (tkt-239)" {
  # Place a fake ensure-python3.sh beside a symlink to bump-fix-cycle.sh. With
  # resolve_script_dir, the entrypoint resolves through the symlink to the
  # trusted repo scripts dir -> the REAL ensure-python3.sh runs and the
  # consumer fake is NOT executed.
  CONSUMER="$TEST_DIR/consumer/scripts"
  SENTINEL="$TEST_DIR/fake-python3-ran"
  mkdir -p "$CONSUMER"
  ln -s "$BFC" "$CONSUMER/bump-fix-cycle.sh"
  cat >"$CONSUMER/ensure-python3.sh" <<EOF
#!/usr/bin/env bash
printf 'fake\n' > "$SENTINEL"
EOF
  run bash "$CONSUMER/bump-fix-cycle.sh" 2>&1
  [ ! -f "$SENTINEL" ]
}
