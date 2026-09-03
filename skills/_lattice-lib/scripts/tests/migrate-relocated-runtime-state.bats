#!/usr/bin/env bats
# Tests for migrate-relocated-runtime-state.sh (spc-282 A7, ADR-011).

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIGRATE="$SCRIPT_DIR/migrate-relocated-runtime-state.sh"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mig.XXXXXX")"
  export TEST_DIR
  LATTICE="$TEST_DIR/.lattice"
  mkdir -p "$LATTICE/.coordinator" "$LATTICE/.transition-ledger"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "removes stale in-repo gate markers + coordinator dir" {
  touch "$LATTICE/.batch-work-active"
  touch "$LATTICE/.batch-merge-authorized"
  touch "$LATTICE/.coordinator/b1.json"
  run bash "$MIGRATE" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$LATTICE/.batch-work-active" ]
  [ ! -e "$LATTICE/.batch-merge-authorized" ]
  [ ! -d "$LATTICE/.coordinator" ]
  printf '%s\n' "$output" | grep -qF "removed 3"
}

@test "removes stale transition-ledger .lock sidecars but keeps .jsonl" {
  touch "$LATTICE/.transition-ledger/tkt-X.jsonl"
  touch "$LATTICE/.transition-ledger/tkt-X.lock"
  run bash "$MIGRATE" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$LATTICE/.transition-ledger/tkt-X.lock" ]
  [ -f "$LATTICE/.transition-ledger/tkt-X.jsonl" ]
}

@test "idempotent: re-run is a no-op (no error, no removal)" {
  touch "$LATTICE/.batch-work-active"
  bash "$MIGRATE" "$TEST_DIR" 2>/dev/null
  run bash "$MIGRATE" "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$LATTICE/.batch-work-active" ]
}

@test "no-op when .lattice is absent" {
  rm -rf "$TEST_DIR/.lattice"
  run bash "$MIGRATE" "$TEST_DIR"
  [ "$status" -eq 0 ]
}
