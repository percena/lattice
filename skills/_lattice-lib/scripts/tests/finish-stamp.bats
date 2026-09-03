#!/usr/bin/env bats
# Tests for finish-stamp.py: pure-Python binder + ledger stamp (spc-416 A9).
#
# Calls finish-stamp.py DIRECTLY (not via finish-ledger.sh) to test the stamp
# logic in isolation. Uses --merged-at/--pr-state/--pr-url overrides so no
# gh/network is required. Covers all 5 A9 dry-run scenarios:
#   1. Normal (pr-open→closed)
#   2. Direct jump (in-progress→closed)
#   3. Idempotent (already closed → no-op)
#   4. Mode C repair (missing edge → insert + stamp)
#   5. Staging failure (gitignored → exit non-zero)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export FS="$REPO_ROOT/skills/_lattice-lib/scripts/finish-stamp.py"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fs.XXXXXX")"
  REPO="$TEST_DIR/repo"
  export LATTICE_HOME="$REPO/.lattice"
  BINDER_DIR="$REPO/.lattice/tickets/tkt-7-demo"
  mkdir -p "$BINDER_DIR/.transition-ledger" 2>/dev/null || mkdir -p "$BINDER_DIR"
  LEDGER_DIR="$REPO/.lattice/.transition-ledger"
  mkdir -p "$LEDGER_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  BINDER="$BINDER_DIR/README.md"
  LEDGER="$LEDGER_DIR/tkt-7.jsonl"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Minimal binder template — finish-stamp.py reads | status |, | prs |,
# | updated |, and the ## Finish section.
write_fresh_binder() {
  local status="${1:-open}"
  local prs="${2:-(none yet)}"
  cat >"$BINDER" <<MD
# tkt-7-demo

| field | value |
| --- | --- |
| status | $status |
| prs | $prs |
| updated | 2026-08-01T00:00:00Z |

## Acceptance

- [ ] **A1** thing

## Finish

- (none yet)
MD
}

# Write a ledger entry (JSONL).
write_ledger_entry() {
  local from="$1" to="$2" reason="${3:-test}"
  local ts="2026-08-01T00:00:0${RANDOM:0:1}Z"
  printf '{"ts":"%s","ticket":"tkt-7","from":"%s","to":"%s","owner":"agent","reason":"%s","guard":"%s","trace":"test","metric":"test"}\n' \
    "$ts" "$from" "$to" "$reason" "$reason" >>"$LEDGER"
}

# Arg 1 = the JSON field to extract from the last ledger line.
last_ledger_field() {
  local field="$1"
  tail -1 "$LEDGER" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('$field', ''))
except Exception:
    print('')
"
}

@test "A9-1 normal: pr-open→closed stamps binder + ledger" {
  write_fresh_binder "pr-open" "(none yet)"
  run python3 "$FS" --binder "$BINDER" --pr 42 \
    --merged-at 2026-08-15T12:00:00Z --pr-state MERGED \
    --pr-url "https://github.com/percena/lattice/pull/42"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "finish-stamp: stamped"
  printf '%s\n' "$output" | grep -qF "flip: 1"
  # Binder status flipped to closed
  grep -q '| status | closed |' "$BINDER"
  # ## Finish has the merged line
  grep -q 'pr-42 merged: 2026-08-15T12:00:00Z' "$BINDER"
  # Ledger has pr-open→closed entry
  [ "$(last_ledger_field from)" = "pr-open" ]
  [ "$(last_ledger_field to)" = "closed" ]
  # Binder + ledger staged
  printf '%s\n' "$output" | grep -qF "staged binder + ledger"
}

@test "A9-2 direct jump: in-progress→closed stamps + anomaly line" {
  write_fresh_binder "in-progress" "(none yet)"
  run python3 "$FS" --binder "$BINDER" --pr 42 \
    --merged-at 2026-08-15T12:00:00Z --pr-state MERGED \
    --pr-url "https://github.com/percena/lattice/pull/42"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "flip: 1"
  grep -q '| status | closed |' "$BINDER"
  # Ledger has in-progress→closed (direct jump, not pr-open→closed)
  [ "$(last_ledger_field from)" = "in-progress" ]
  [ "$(last_ledger_field to)" = "closed" ]
  # Anomaly line about direct jump
  grep -q 'anomaly: direct jump' "$BINDER"
}

@test "A9-3 idempotent: already closed + consistent ledger → no-op (A3)" {
  # Write an already-stamped binder (## Finish has the merged line, status=closed)
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| field | value |
| --- | --- |
| status | closed |
| prs | pr-42 — https://github.com/percena/lattice/pull/42 |
| updated | 2026-08-01T00:00:00Z |

## Acceptance

- [ ] **A1** thing

## Finish

- pr-42 merged: 2026-08-15T12:00:00Z — https://github.com/percena/lattice/pull/42 (base merge)
MD
  # Pre-seed ledger with pr-open→closed (consistent)
  write_ledger_entry "pr-open" "closed" "merge"
  # Make an initial commit so git add has a base
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "base"
  run python3 "$FS" --binder "$BINDER" --pr 42 \
    --merged-at 2026-08-15T12:00:00Z --pr-state MERGED \
    --pr-url "https://github.com/percena/lattice/pull/42"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "no change.*idempotent"
  # Nothing staged
  run git -C "$REPO" diff --cached --name-only
  [ -z "$output" ]
}

@test "A9-4 Mode C repair: missing edge inserted before stamp" {
  write_fresh_binder "pr-open" "(none yet)"
  # Pre-seed ledger with queued→in-progress (last to=in-progress, but binder
  # is at pr-open — gap. Mode C should insert in-progress→pr-open before
  # stamping →closed).
  write_ledger_entry "queued" "in-progress" "start"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "base"
  run python3 "$FS" --binder "$BINDER" --pr 42 \
    --merged-at 2026-08-15T12:00:00Z --pr-state MERGED \
    --pr-url "https://github.com/percena/lattice/pull/42"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "Mode C repair"
  grep -q '| status | closed |' "$BINDER"
  # Ledger should have 3 entries: queued→in-progress, in-progress→pr-open, pr-open→closed
  local lines
  lines=$(wc -l < "$LEDGER")
  [ "$lines" -eq 3 ]
  # Last entry is pr-open→closed
  [ "$(last_ledger_field from)" = "pr-open" ]
  [ "$(last_ledger_field to)" = "closed" ]
  # Second entry is in-progress→pr-open (the Mode C repair)
  local second_to
  second_to=$(sed -n '2p' "$LEDGER" | python3 -c "import json,sys; print(json.load(sys.stdin).get('to',''))")
  [ "$second_to" = "pr-open" ]
}

@test "A9-5 staging failure: gitignored ledger → exit non-zero (A5)" {
  write_fresh_binder "pr-open" "(none yet)"
  # Gitignore the ledger dir so git add of the ledger fails
  printf '.lattice/.transition-ledger/\n' > "$REPO/.gitignore"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "base"
  run python3 "$FS" --binder "$BINDER" --pr 42 \
    --merged-at 2026-08-15T12:00:00Z --pr-state MERGED \
    --pr-url "https://github.com/percena/lattice/pull/42"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qiE "ERROR.*(git add|NOT staged|staging)"
}

@test "A1-fix: already closed + no ledger → open→closed repair (not closed→closed)" {
  # spc-424 A1: binder already stamped to closed (e.g. by a prior partial run
  # that wrote the binder but failed before recording the ledger). No ledger
  # file exists. finish-stamp should use the legal `open→closed` legacy edge
  # (transition_table.py:157), NOT the illegal `closed→closed`.
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| field | value |
| --- | --- |
| status | closed |
| prs | pr-42 — https://github.com/percena/lattice/pull/42 |
| updated | 2026-08-01T00:00:00Z

## Acceptance

- [ ] **A1** thing

## Finish

- pr-42 merged: 2026-08-15T12:00:00Z — https://github.com/percena/lattice/pull/42 (base merge)
MD
  # No ledger file exists at all
  git -C "$REPO" add -A && git -C "$REPO" commit -qm "base"
  run python3 "$FS" --binder "$BINDER" --pr 42 \
    --merged-at 2026-08-15T12:00:00Z --pr-state MERGED \
    --pr-url "https://github.com/percena/lattice/pull/42"
  [ "$status" -eq 0 ]
  # Ledger was created with open→closed (NOT closed→closed which would fail)
  [ -f "$LEDGER" ]
  [ "$(last_ledger_field from)" = "open" ]
  [ "$(last_ledger_field to)" = "closed" ]
  printf '%s\n' "$output" | grep -qF "ledger repair"
}
