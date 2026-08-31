#!/usr/bin/env bats
# Tests for state-dir-gc.sh (spc-282 A6, ADR-011) — stale runtime-state GC.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GC="$SCRIPT_DIR/state-dir-gc.sh"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sgc.XXXXXX")"
  export TEST_DIR
  STATE_HOME="$TEST_DIR/state-home"
  mkdir -p "$STATE_HOME/.coordinator" "$STATE_HOME/.transition-ledger"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "removes a stale .batch-work-active marker older than threshold" {
  touch "$STATE_HOME/.batch-work-active"
  # backdate 48h ago (threshold default 24h)
  touch -d "2 days ago" "$STATE_HOME/.batch-work-active" 2>/dev/null || touch -t 202601010000 "$STATE_HOME/.batch-work-active"
  run bash "$GC" --state-home "$STATE_HOME" --stale-hours 24
  [ "$status" -eq 0 ]
  [ ! -f "$STATE_HOME/.batch-work-active" ]
  printf '%s\n' "$output" | grep -qF "removed 1"
}

@test "keeps a fresh .batch-work-active marker younger than threshold" {
  touch "$STATE_HOME/.batch-work-active"
  run bash "$GC" --state-home "$STATE_HOME" --stale-hours 24
  [ "$status" -eq 0 ]
  [ -f "$STATE_HOME/.batch-work-active" ]
  printf '%s\n' "$output" | grep -qF "removed 0"
}

@test "removes stale .batch-merge-authorized + coordinator json + ledger .lock" {
  touch -d "2 days ago" "$STATE_HOME/.batch-merge-authorized" 2>/dev/null || touch -t 202601010000 "$STATE_HOME/.batch-merge-authorized"
  touch -d "2 days ago" "$STATE_HOME/.coordinator/b1.json" 2>/dev/null || touch -t 202601010000 "$STATE_HOME/.coordinator/b1.json"
  touch -d "2 days ago" "$STATE_HOME/.transition-ledger/tkt-X.lock" 2>/dev/null || touch -t 202601010000 "$STATE_HOME/.transition-ledger/tkt-X.lock"
  run bash "$GC" --state-home "$STATE_HOME" --stale-hours 24
  [ "$status" -eq 0 ]
  [ ! -f "$STATE_HOME/.batch-merge-authorized" ]
  [ ! -f "$STATE_HOME/.coordinator/b1.json" ]
  [ ! -f "$STATE_HOME/.transition-ledger/tkt-X.lock" ]
  printf '%s\n' "$output" | grep -qF "removed 3"
}

@test "no-op when state home is absent (never creates markers)" {
  run bash "$GC" --state-home "$TEST_DIR/does-not-exist"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "nothing to GC"
  [ ! -d "$TEST_DIR/does-not-exist" ]
}
