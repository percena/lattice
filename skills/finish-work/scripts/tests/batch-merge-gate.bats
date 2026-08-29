#!/usr/bin/env bats
# Tests for skills/finish-work/scripts/batch-merge-gate.sh (spc-187 A1, ADR-007).
# Exercises the scripted marker lifecycle: check, status, remove-with-trace.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE_SCRIPT="$SCRIPT_DIR/batch-merge-gate.sh"
  export LATTICE_BATCH_GATE_HOME="${BATS_TEST_TMPDIR:-$(mktemp -d)}/batch-gate-home"
  mkdir -p "$LATTICE_BATCH_GATE_HOME"
}

@test "check: marker absent -> exit 0 (allowed)" {
  run "$GATE_SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "check: marker present -> exit 1 (blocked)" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run "$GATE_SCRIPT" --check
  [ "$status" -eq 1 ]
}

@test "check: marker present + authorized-merge flag -> exit 0 (escaped)" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  printf 'reason: user-authorized: batch done, merge #7\n' \
    >"$LATTICE_BATCH_GATE_HOME/.batch-merge-authorized"
  run "$GATE_SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "status: reports marker_present + allowed=false when blocked" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run "$GATE_SCRIPT" --status
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.marker_present == true'
  echo "$output" | jq -e '.allowed == false'
  echo "$output" | jq -e '.escape_present == false'
}

@test "status: reports allowed=true when marker absent" {
  run "$GATE_SCRIPT" --status
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.marker_present == false'
  echo "$output" | jq -e '.allowed == true'
}

@test "remove: requires --reason (exit 2 without)" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run "$GATE_SCRIPT" --remove
  [ "$status" -eq 2 ]
  # marker still present
  [ -f "$LATTICE_BATCH_GATE_HOME/.batch-work-active" ]
}

@test "remove: deletes marker and emits a structured trace line" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run "$GATE_SCRIPT" --remove --reason "user-authorized: merge #7 after review"
  [ "$status" -eq 0 ]
  [ ! -f "$LATTICE_BATCH_GATE_HOME/.batch-work-active" ]
  printf '%s\n' "$output" | grep -qF "Decision journal entry"
  printf '%s\n' "$output" | grep -qF "rule_id=batch-merge-gate"
  printf '%s\n' "$output" | grep -qF "user-authorized: merge #7 after review"
  printf '%s\n' "$output" | grep -qF "authorizer=operator"
}

@test "remove: no-op when marker already absent" {
  run "$GATE_SCRIPT" --remove --reason "user-authorized: nothing to clear"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "already absent"
}

@test "remove: also clears a stale authorized-merge flag" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  printf 'reason: user-authorized: stale\n' \
    >"$LATTICE_BATCH_GATE_HOME/.batch-merge-authorized"
  run "$GATE_SCRIPT" --remove --reason "user-authorized: merge #7"
  [ "$status" -eq 0 ]
  [ ! -f "$LATTICE_BATCH_GATE_HOME/.batch-merge-authorized" ]
}
