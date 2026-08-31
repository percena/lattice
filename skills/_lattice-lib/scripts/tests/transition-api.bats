#!/usr/bin/env bats
# transition-api + validator ledger replay (spc-254 A3): the API records legal
# flips, refuses illegal edges and escape-required edges without an operator
# override, and the validator replays the ledger to reject an illegal edge
# between two legal snapshots.

setup() {
  SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  export API="$SCRIPT_DIR/transition-api.py"
  export VALIDATOR="$REPO_ROOT/tools/validate-lattice-artifacts.py"
  export LATTICE_HOME="$BATS_RUN_TMPDIR/lattice"
  mkdir -p "$LATTICE_HOME"
  rm -f "$LATTICE_HOME/.transition-ledger.jsonl"
}

@test "legal edge exits 0 (queued -> in-progress)" {
  run python3 "$API" legal queued in-progress
  [ "$status" -eq 0 ]
}

@test "illegal edge exits non-zero (rework -> pr-open direct)" {
  run python3 "$API" legal rework pr-open
  [ "$status" -ne 0 ]
}

@test "record appends a legal ledger entry" {
  run python3 "$API" record tkt-1 queued in-progress system spawn
  [ "$status" -eq 0 ]
  grep -q '"from":"queued"' "$LATTICE_HOME/.transition-ledger.jsonl"
  grep -q '"to":"in-progress"' "$LATTICE_HOME/.transition-ledger.jsonl"
}

@test "record refuses an illegal edge (no ledger entry written)" {
  run python3 "$API" record tkt-1 rework pr-open agent push
  [ "$status" -eq 1 ]
  [ ! -s "$LATTICE_HOME/.transition-ledger.jsonl" ]
}

@test "escape-required edge refused without operator override (exit 2)" {
  run python3 "$API" record tkt-1 parked pr-open agent force
  [ "$status" -eq 2 ]
  [ ! -s "$LATTICE_HOME/.transition-ledger.jsonl" ]
}

@test "escape-required edge recorded with operator override" {
  run python3 "$API" record tkt-1 parked pr-open agent force \
    --force-side-state-reason "operator: merge urgency"
  [ "$status" -eq 0 ]
  grep -q '"force_side_state_reason":"operator: merge urgency"' \
    "$LATTICE_HOME/.transition-ledger.jsonl"
}

@test "validator replays ledger: legal entry yields no illegal_transition_edge" {
  python3 "$API" record tkt-1 queued in-progress system spawn >/dev/null
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  run grep -qF "illegal_transition_edge" <<<"$output"
  [ "$status" -ne 0 ]
}

@test "validator replays ledger: illegal edge fails the run" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-1","from":"rework","to":"pr-open","owner":"agent","reason":"push","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -q "illegal_transition_edge" <<<"$output"
}

@test "validator replays ledger: escape-required without override fails" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-1","from":"parked","to":"pr-open","owner":"agent","reason":"force","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -q "illegal_transition_edge" <<<"$output"
}
