#!/usr/bin/env bats

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export VAL="$REPO_ROOT/tools/validate-lattice-artifacts.py"
  export FIX="$REPO_ROOT/tools/tests/fixtures/lattice-artifacts"
}

@test "pass fixture is clean" {
  run python3 "$VAL" --home "$FIX/pass" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
}

@test "fail fixture reports invalid status, covers, onesided edge, malformed review id" {
  run python3 "$VAL" --home "$FIX/fail" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"ok": false'* ]]
  [[ "$output" == *invalid_ticket_status* ]]
  [[ "$output" == *covers_not_on_spec* ]]
  [[ "$output" == *onesided_spec_ticket_edge* ]]
  [[ "$output" == *malformed_review_id* ]]
}

@test "binder field rows come from the first table only; example table cannot shadow" {
  # tkt-9 binder card (first table) has no status row; status comes from the
  # TL;DR. A later docs/example table carrying status/covers rows must not
  # shadow the binder card.
  run python3 "$VAL" --home "$FIX/first-table" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
}

@test "slugless spec filename derives id without the .md extension" {
  # spc-12.md has no front-matter id and no slug; fallback must yield spc-12.
  run python3 "$VAL" --home "$FIX/first-table" --json
  [ "$status" -eq 0 ]
  [[ "$output" != *malformed_spec_id* ]]
  [[ "$output" != *'spc-12.md'*'is not spc-N'* ]]
}

@test "bold A-id in prose outside Acceptance is not coverable" {
  # spc-8 mentions **A7** in Notes prose; tkt-8 covers A7 — must fail because
  # only Acceptance-section A-ids are coverable.
  run python3 "$VAL" --home "$FIX/acceptance-scope" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *covers_not_on_spec* ]]
  [[ "$output" == *"A7"* ]]
}

@test "working FSM states (pr-open) and closed-with-Finish pass clean" {
  run python3 "$VAL" --home "$FIX/status-fsm" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" == *'"warning_count": 0'* ]]
}

@test "unknown status value fails" {
  run python3 "$VAL" --home "$FIX/status-fsm-fail" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *invalid_ticket_status* ]]
  [[ "$output" == *"'bogus'"* ]]
}

@test "closed without real Finish ledger content fails" {
  run python3 "$VAL" --home "$FIX/status-fsm-fail" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *closed_without_finish* ]]
  [[ "$output" == *tkt-63-closed-empty* ]]
}

@test "legacy open warns but passes (lazy migration)" {
  run python3 "$VAL" --home "$FIX/status-legacy-open" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" == *legacy_open_status* ]]
  [[ "$output" == *'"warning_count": 1'* ]]
}

@test "prose backtick mention must not mask onesided_spec_ticket_edge" {
  # spec spc-4 omits tkt-4 from authoritative `tickets:` but mentions `tkt-4`
  # in prose; the one-sided edge must still fire.
  run python3 "$VAL" --home "$FIX/onesided-prose" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"ok": false'* ]]
  [[ "$output" == *onesided_spec_ticket_edge*tkt-4*spc-4* ]]
}
