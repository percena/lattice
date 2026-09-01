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
  mkdir -p "$LATTICE_HOME/.transition-ledger"
  rm -rf "$LATTICE_HOME/.transition-ledger"
  mkdir -p "$LATTICE_HOME/.transition-ledger"
}

@test "legal edge exits 0 (queued -> in-progress)" {
  run python3 "$API" legal queued in-progress
  [ "$status" -eq 0 ]
}

@test "illegal edge exits non-zero (closed -> queued: terminal is not a source)" {
  run python3 "$API" legal closed queued
  [ "$status" -ne 0 ]
}

@test "record appends a legal ledger entry" {
  run python3 "$API" record tkt-1 queued in-progress system spawn
  [ "$status" -eq 0 ]
  grep -q '"from":"queued"' "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
  grep -q '"to":"in-progress"' "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
}

@test "record refuses an illegal edge (no ledger entry written)" {
  run python3 "$API" record tkt-1 closed queued agent reopen
  [ "$status" -eq 1 ]
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl" ]
}

@test "escape-required edge refused without operator override (exit 2)" {
  run python3 "$API" record tkt-1 parked pr-open agent force
  [ "$status" -eq 2 ]
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl" ]
}

@test "escape-required edge recorded with operator override" {
  run python3 "$API" record tkt-1 parked pr-open agent force \
    --force-side-state-reason "operator: merge urgency"
  [ "$status" -eq 0 ]
  grep -q '"force_side_state_reason":"operator: merge urgency"' \
    "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
}

@test "validator replays ledger: legal entry yields no illegal_transition_edge" {
  python3 "$API" record tkt-1 queued in-progress system spawn >/dev/null
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  run grep -qF "illegal_transition_edge" <<<"$output"
  [ "$status" -ne 0 ]
}

@test "validator replays ledger: illegal edge fails the run" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-1","from":"closed","to":"queued","owner":"agent","reason":"reopen","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -q "illegal_transition_edge" <<<"$output"
}

@test "validator replays ledger: escape-required without override fails" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-1","from":"parked","to":"pr-open","owner":"agent","reason":"force","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -q "illegal_transition_edge" <<<"$output"
}

# ---------------------------------------------------------------------------
# spc-270 A1.5: the validator's inline replay enforces the three continuity
# invariants (identity / continuity / snapshot) so CI catches ledger↔binder
# drift — the finish-ledger close-without-ledger-entry class — not just edge
# legality. These mirror transition-api replay-ledger tests 19-22 but exercise
# the validator's own replay path.
# ---------------------------------------------------------------------------

@test "validator flags snapshot mismatch: ledger final to != binder status" {
  B=$(make_binder tkt-30)   # binder stays queued
  python3 "$API" record tkt-30 queued in-progress system spawn >/dev/null
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -qF "transition_ledger_snapshot_mismatch" <<<"$output"
}

@test "validator flags discontinuity: entry.from != prior entry.to" {
  printf '%s\n%s\n' \
    '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-31","from":"queued","to":"in-progress","owner":"system","reason":"spawn","force_side_state_reason":null}' \
    '{"ts":"2026-08-31T00:00:01Z","ticket":"tkt-31","from":"parked","to":"queued","owner":"human","reason":"x","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-31.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -qF "transition_ledger_discontinuity" <<<"$output"
}

@test "validator flags identity mismatch: entry ticket != ledger file ticket" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-999","from":"queued","to":"in-progress","owner":"system","reason":"spawn","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-32.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -qF "transition_ledger_identity_mismatch" <<<"$output"
}

@test "validator passes a clean chain whose final snapshot matches the binder" {
  B=$(make_binder tkt-33)
  python3 "$API" commit tkt-33 in-progress system spawn >/dev/null
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
}

# --- spc-270 A1.1: atomic binder-bound `commit` ---------------------------

# Minimal binder with the field-table rows the writers ship. Returns the path.
make_binder() {
  local id="$1" slug="${2:-slice}"
  local dir="$LATTICE_HOME/tickets/${id}-${slug}"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MD
# ${id} — ${slug}

| Field | Value |
| --- | --- |
| status | queued |
| wait_reason | (none) |
| updated | 2026-08-31T00:00:00Z |
MD
  echo "$dir/README.md"
}

@test "commit atomically mutates binder status/wait_reason/updated + ledger" {
  B=$(make_binder tkt-10)
  run python3 "$API" commit tkt-10 in-progress system spawn
  [ "$status" -eq 0 ]
  grep -q '| status | in-progress |' "$B"
  grep -q '| wait_reason | (none) |' "$B"
  # updated stamp bumped off the seed value (any real ISO-8601 UTC stamp
  # that is not the seed 2026-08-31T00:00:00Z).
  grep -qE '\| updated \| 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \|' "$B"
  if grep -qF '| updated | 2026-08-31T00:00:00Z |' "$B"; then false; fi
  grep -q '"from":"queued"' "$LATTICE_HOME/.transition-ledger/tkt-10.jsonl"
  grep -q '"to":"in-progress"' "$LATTICE_HOME/.transition-ledger/tkt-10.jsonl"
}

@test "commit refuses illegal edge: binder and ledger unchanged (fail-close)" {
  B=$(make_binder tkt-11)
  # queued -> in-progress is legal; in-progress -> queued is NOT an edge
  # (no return-to-queue; the schema intentionally omits it).
  python3 "$API" commit tkt-11 in-progress system spawn >/dev/null
  run python3 "$API" commit tkt-11 queued agent skip
  [ "$status" -eq 1 ]
  grep -q '| status | in-progress |' "$B"
  # The refused flip recorded no second ledger entry.
  [ "$(wc -l < "$LATTICE_HOME/.transition-ledger/tkt-11.jsonl")" -eq 1 ]
}

@test "commit refuses escape-required edge without override (exit 2, no write)" {
  B=$(make_binder tkt-12)
  # First move queued -> in-progress -> parked so a parked->pr-open force is reachable.
  python3 "$API" commit tkt-12 in-progress system spawn >/dev/null
  python3 "$API" commit tkt-12 parked agent park >/dev/null
  run python3 "$API" commit tkt-12 pr-open agent force
  [ "$status" -eq 2 ]
  grep -q '| status | parked |' "$B"
}

@test "commit enforces coupled wait_reason for stuck (fail-close)" {
  B=$(make_binder tkt-13)
  python3 "$API" commit tkt-13 in-progress system spawn >/dev/null
  run python3 "$API" commit tkt-13 stuck agent block
  [ "$status" -eq 1 ]
  grep -q '| status | in-progress |' "$B"
  # No ledger entry recorded for the refused flip.
  if grep -q '"to":"stuck"' "$LATTICE_HOME/.transition-ledger/tkt-13.jsonl"; then false; fi
}

@test "commit accepts stuck with --wait-reason unblock" {
  B=$(make_binder tkt-14)
  python3 "$API" commit tkt-14 in-progress system spawn >/dev/null
  run python3 "$API" commit tkt-14 stuck agent block --wait-reason unblock
  [ "$status" -eq 0 ]
  grep -q '| status | stuck |' "$B"
  grep -q '| wait_reason | unblock |' "$B"
}

@test "commit --from continuity guard rejects a stale expected prior" {
  B=$(make_binder tkt-15)
  # Binder is queued; caller asserts from=in-progress (wrong) -> refused.
  run python3 "$API" commit tkt-15 pr-open agent open --from in-progress
  [ "$status" -eq 1 ]
  grep -q '| status | queued |' "$B"
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-15.jsonl" ]
}

@test "commit --dry-run writes neither binder nor ledger" {
  B=$(make_binder tkt-16)
  run python3 "$API" commit tkt-16 in-progress system spawn --dry-run
  [ "$status" -eq 0 ]
  grep -q '| status | queued |' "$B"
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-16.jsonl" ]
}

@test "commit records the legal pr-open -> pr-open rebase-void self-edge" {
  B=$(make_binder tkt-17)
  python3 "$API" commit tkt-17 in-progress system spawn >/dev/null
  python3 "$API" commit tkt-17 pr-open agent open >/dev/null
  run python3 "$API" commit tkt-17 pr-open system rebase-void
  [ "$status" -eq 0 ]
  grep -q '"from":"pr-open"' "$LATTICE_HOME/.transition-ledger/tkt-17.jsonl"
  grep -q '"to":"pr-open"' "$LATTICE_HOME/.transition-ledger/tkt-17.jsonl"
}

# --- spc-270 A1.2: fault injection (no partial state on write failure) ------

@test "commit aborts on ledger-write failure: binder unchanged, no temp residue" {
  B=$(make_binder tkt-20)
  # One clean transition first so the binder is in-progress and a further
  # flip is legal (in-progress -> parked).
  python3 "$API" commit tkt-20 in-progress system spawn >/dev/null
  ledger="$LATTICE_HOME/.transition-ledger/tkt-20.jsonl"
  before_path="$LATTICE_HOME/.binder-before-20"
  cp "$B" "$before_path"
  before_lines=$(wc -l < "$ledger")
  # Make the ledger dir unwritable so the append in the transaction fails.
  chmod 000 "$LATTICE_HOME/.transition-ledger"
  run python3 "$API" commit tkt-20 parked agent park
  chmod 755 "$LATTICE_HOME/.transition-ledger"
  [ "$status" -eq 3 ]
  # Binder byte-identical to pre-attempt snapshot.
  diff "$before_path" "$B"
  # Ledger line count unchanged (no misleading record).
  [ "$(wc -l < "$ledger")" -eq "$before_lines" ]
  # No stray temp file left in the binder directory.
  [ -z "$(find "$LATTICE_HOME/tickets/tkt-20-slice" -name '*.tmp' -print)" ]
}

# --- spc-270 A1.4: replay identity / continuity / snapshot invariants -------

@test "replay flags a ticket-identity mismatch" {
  B=$(make_binder tkt-30)
  printf '%s\n' '{"ticket":"tkt-999","from":"queued","to":"in-progress","owner":"x","reason":"y"}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-30.jsonl"
  run python3 "$API" replay-ledger
  [ "$status" -eq 1 ]
  grep -q 'identity mismatch' <<<"$output"
}

@test "replay flags a discontinuity (entry.from != prior entry.to)" {
  B=$(make_binder tkt-31)
  {
    printf '%s\n' '{"ticket":"tkt-31","from":"queued","to":"in-progress","owner":"x","reason":"y"}'
    printf '%s\n' '{"ticket":"tkt-31","from":"parked","to":"pr-open","owner":"x","reason":"y"}'
  } > "$LATTICE_HOME/.transition-ledger/tkt-31.jsonl"
  run python3 "$API" replay-ledger
  [ "$status" -eq 1 ]
  grep -q 'discontinuity' <<<"$output"
}

@test "replay flags a final-snapshot mismatch vs the binder" {
  B=$(make_binder tkt-32)
  # Ledger claims queued -> in-progress, but the binder is still queued.
  printf '%s\n' '{"ticket":"tkt-32","from":"queued","to":"in-progress","owner":"x","reason":"y"}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-32.jsonl"
  run python3 "$API" replay-ledger
  [ "$status" -eq 1 ]
  grep -q 'snapshot mismatch' <<<"$output"
}

@test "replay passes a clean consistent chain" {
  B=$(make_binder tkt-33)
  python3 "$API" commit tkt-33 in-progress system spawn >/dev/null
  python3 "$API" commit tkt-33 pr-open agent open >/dev/null
  run python3 "$API" replay-ledger
  [ "$status" -eq 0 ]
  grep -q '0 illegal/inconsistent' <<<"$output"
}
