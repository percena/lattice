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

@test "check: unresolvable home + env unset -> exit 1 (fail closed, tkt-239)" {
  # No LATTICE_BATCH_GATE_HOME and not inside a git work tree -> resolve_home
  # fails. The gate must fail CLOSED (exit 1), not silently allow.
  NOGIT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/no-git-cwd"
  mkdir -p "$NOGIT"
  run bash -c "cd '$NOGIT' && unset LATTICE_BATCH_GATE_HOME && '$GATE_SCRIPT' --check"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "could not resolve Lattice state home"
}

@test "check: env override still allows merge when marker absent (tkt-239 regression guard)" {
  # A resolvable home (env override) with no marker -> allowed. Guards against
  # the fail-closed change accidentally firing when home IS resolvable.
  run "$GATE_SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "state dir: marker resolves OUT of repo to fingerprint state home (ADR-011 / spc-282 A1)" {
  # With no override, the marker home resolves to $HOME/.local/state/lattice/<fp>
  # (out-of-repo), NOT .lattice/. Verify the marker never lands under .lattice/.
  TEST_REPO="${BATS_TEST_TMPDIR:-$(mktemp -d)}/repo"
  mkdir -p "$TEST_REPO/.lattice"
  git -C "$TEST_REPO" init -q
  STUB_HOME="${BATS_TEST_TMPDIR:-$(mktemp -d)}/fake-home"
  mkdir -p "$STUB_HOME"
  unset LATTICE_BATCH_GATE_HOME
  unset LATTICE_STATE_HOME
  HOME="$STUB_HOME" run "$GATE_SCRIPT" --status
  [ "$status" -eq 0 ]
  # The resolved home must be under the fake-home state dir.
  printf '%s\n' "$output" | grep -qF "$STUB_HOME/.local/state/lattice/"
}

# ---------------------------------------------------------------------------
# spc-337 A6 (tkt-342) — scripted marker creation + barrier heartbeat
# ---------------------------------------------------------------------------

@test "create: writes batch-id + started lines and prints status JSON (spc-337 A6)" {
  run "$GATE_SCRIPT" --create --batch-id "20260902-4242"
  [ "$status" -eq 0 ]
  marker="$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  [ -f "$marker" ]
  grep -qx 'batch-id: 20260902-4242' "$marker"
  grep -qE '^started: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$marker"
  echo "$output" | jq -e '.marker_present == true'
  echo "$output" | jq -e '.allowed == false'
  echo "$output" | jq -e '.batch_id == "20260902-4242"'
  # The merge gate is now closed (the whole point of the marker).
  run "$GATE_SCRIPT" --check
  [ "$status" -eq 1 ]
}

@test "create: requires --batch-id (exit 2 without)" {
  run "$GATE_SCRIPT" --create
  [ "$status" -eq 2 ]
  [ ! -f "$LATTICE_BATCH_GATE_HOME/.batch-work-active" ]
}

@test "create: idempotent for the same batch-id (content untouched, exit 0)" {
  "$GATE_SCRIPT" --create --batch-id "same-1" >/dev/null
  marker="$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  before=$(cat "$marker")
  run "$GATE_SCRIPT" --create --batch-id "same-1"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "idempotent"
  [ "$(cat "$marker")" = "$before" ]
  echo "$output" | grep -F '{' | jq -e '.batch_id == "same-1"'
}

@test "create: refuses to overwrite a DIFFERENT batch-id without --force (exit 1)" {
  "$GATE_SCRIPT" --create --batch-id "first-batch" >/dev/null
  marker="$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run "$GATE_SCRIPT" --create --batch-id "second-batch"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "DIFFERENT batch"
  printf '%s\n' "$output" | grep -qF "first-batch"
  # First batch still owns the marker.
  grep -qx 'batch-id: first-batch' "$marker"
  if grep -q 'second-batch' "$marker"; then false; fi
}

@test "create: --force overwrites a different batch-id (with a warning)" {
  "$GATE_SCRIPT" --create --batch-id "first-batch" >/dev/null
  marker="$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run "$GATE_SCRIPT" --create --batch-id "second-batch" --force
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "warn: --force overwriting"
  grep -qx 'batch-id: second-batch' "$marker"
  if grep -q 'first-batch' "$marker"; then false; fi
  echo "$output" | grep -F '{' | jq -e '.batch_id == "second-batch"'
}

@test "create: legacy marker without a batch-id line is treated as a different batch (refused without --force)" {
  # A raw-touched marker (pre-spc-337 prose) carries no batch-id line; the
  # gate fails closed rather than silently adopting it.
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run "$GATE_SCRIPT" --create --batch-id "new-batch"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "<none>"
  run "$GATE_SCRIPT" --create --batch-id "new-batch" --force
  [ "$status" -eq 0 ]
  grep -qx 'batch-id: new-batch' "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
}

@test "touch: refreshes the marker mtime (barrier heartbeat, ADR-011)" {
  "$GATE_SCRIPT" --create --batch-id "hb-1" >/dev/null
  marker="$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  # Age the marker into the past, then heartbeat it.
  touch -d '2000-01-01T00:00:00Z' "$marker" 2>/dev/null || touch -t 200001010000 "$marker"
  old_mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker")
  run "$GATE_SCRIPT" --touch
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "touched:"
  new_mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker")
  [ "$new_mtime" -gt "$old_mtime" ]
  # Content (batch-id) untouched by the heartbeat.
  grep -qx 'batch-id: hb-1' "$marker"
}

@test "touch: marker absent -> warning only, exit 0 (never fails the wave)" {
  run "$GATE_SCRIPT" --touch
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "warn: marker absent"
  [ ! -f "$LATTICE_BATCH_GATE_HOME/.batch-work-active" ]
}

@test "status: reports batch_id from a --create'd marker; --remove still clears it" {
  "$GATE_SCRIPT" --create --batch-id "cycle-1" >/dev/null
  run "$GATE_SCRIPT" --status
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.batch_id == "cycle-1"'
  run "$GATE_SCRIPT" --remove --reason "user-authorized: batch cycle-1 reviewed"
  [ "$status" -eq 0 ]
  [ ! -f "$LATTICE_BATCH_GATE_HOME/.batch-work-active" ]
  run "$GATE_SCRIPT" --status
  echo "$output" | jq -e '.batch_id == ""'
}
