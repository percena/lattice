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

@test "header Status copy contradicting the field table warns (does not fail)" {
  # tkt-70: header in-progress vs table queued → exactly one warning; the home
  # still passes (warnings never fail the run).
  run python3 "$VAL" --home "$FIX/header-status" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" == *header_status_mismatch* ]]
  [[ "$output" == *tkt-70-mismatch* ]]
  [[ "$output" == *'"warning_count": 1'* ]]
}

@test "matching, legacy-open, and prose-mention headers do not warn" {
  # tkt-71 header==table, tkt-72 legacy-coarse open header (exempt), tkt-73
  # prose mention of **Status:** below the binder card — none may fire.
  run python3 "$VAL" --home "$FIX/header-status" --json
  [ "$status" -eq 0 ]
  [[ "$output" != *tkt-71-match* ]]
  [[ "$output" != *tkt-72-legacy-header* ]]
  [[ "$output" != *tkt-73-prose-mention* ]]
}

@test "malformed filled prs row warns (does not fail)" {
  # tkt-80: legacy `URL · pr-N — URL` shape → exactly one warning; the home
  # still passes (warning-level permanently — adopt flows may reintroduce
  # legacy rows).
  run python3 "$VAL" --home "$FIX/prs-row" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" == *prs_row_format* ]]
  [[ "$output" == *tkt-80-malformed* ]]
  [[ "$output" == *'"warning_count": 1'* ]]
}

@test "canonical, comma-separated multi-PR, and placeholder prs rows are silent" {
  # tkt-81 `pr-81 — URL`, tkt-83 `pr-83 — URL, pr-84 — URL`, tkt-82
  # `(none — rides tkt-81 PR)` placeholder — none may fire.
  run python3 "$VAL" --home "$FIX/prs-row" --json
  [ "$status" -eq 0 ]
  [[ "$output" != *tkt-81-canonical* ]]
  [[ "$output" != *tkt-82-placeholder* ]]
  [[ "$output" != *tkt-83-multi* ]]
}

@test "prose backtick mention must not mask onesided_spec_ticket_edge" {
  # spec spc-4 omits tkt-4 from authoritative `tickets:` but mentions `tkt-4`
  # in prose; the one-sided edge must still fire.
  run python3 "$VAL" --home "$FIX/onesided-prose" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"ok": false'* ]]
  [[ "$output" == *onesided_spec_ticket_edge*tkt-4*spc-4* ]]
}

# tkt-90: inverse coherence — a merged Finish ledger requires terminal status.

@test "merged Finish ledger with working status fails; cancel ledger is exempt" {
  run python3 "$VAL" --home "$FIX/finish-status-mismatch" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *finish_without_terminal_status* ]]
  [[ "$output" == *tkt-70-merged-but-pr-open* ]]
  [[ "$output" != *tkt-71-cancel-ok* ]]
}

@test "two binder dirs claiming one tkt id fail with duplicate_ticket_id" {
  run python3 "$VAL" --home "$FIX/dup-ticket-id" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *duplicate_ticket_id* ]]
  [[ "$output" == *tkt-3-first* ]]
  [[ "$output" == *tkt-3-second* ]]
}

# spc-104 A1: feature-map format + status vocabulary (checked when the file exists).

@test "well-formed feature map passes clean" {
  run python3 "$VAL" --home "$FIX/feature-map" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"warning_count": 0'* ]]
}

@test "feature map: unknown status errors, empty oracle warns" {
  run python3 "$VAL" --home "$FIX/feature-map-fail" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *feature_map_status* ]]
  [[ "$output" == *"'verified'"* ]]
  [[ "$output" == *feature_map_row_format* ]]
}

# tkt-121: three latent validator defects — status fallback scope, finish
# placeholder family, acceptance-heading A-ids.

@test "status fallback is scoped — body prose **Status:** is not misread as status" {
  # tkt-200: binder card (first table) has no status row; body acceptance prose
  # mentions the literal **Status:** marker. The scoped fallback
  # (tldr_header_status, blockquote lines before the first table) finds none,
  # so no invalid_ticket_status fires.
  run python3 "$VAL" --home "$FIX/status-prose-mention" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" != *invalid_ticket_status* ]]
  [[ "$output" != *tkt-200* ]]
}

@test "finish ledger exempts the whole (none…) placeholder family" {
  # tkt-201: status closed, ## Finish carries "(none — rides tkt-5 PR)" — a
  # placeholder (PRS_PLACEHOLDER_RE), not the literal "(none yet)". The family
  # is exempt, so has_finish_ledger returns False and closed_without_finish fires.
  run python3 "$VAL" --home "$FIX/finish-placeholder-family" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *closed_without_finish* ]]
  [[ "$output" == *tkt-201-placeholder* ]]
}

@test "A-ids inline on the Acceptance heading line are coverable" {
  # spc-202 declares "## Acceptance — **A1**, **A2**"; tkt-202 covers A1.
  # Heading-line A-ids must register, so covers_not_on_spec must NOT fire.
  run python3 "$VAL" --home "$FIX/acceptance-heading-aids" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" != *covers_not_on_spec* ]]
  [[ "$output" != *tkt-202* ]]
}

# tkt-123: bounded-loop invariant — fix_cycles field-table row + cap (>2 warns).

@test "fix_cycles >2 warns (bounded-loop cap); ≤2 and missing are clean" {
  # tkt-203 has fix_cycles 3 → fix_cycles_exceeded warning (run still passes —
  # warning level). tkt-204 has fix_cycles 2 → no warning.
  run python3 "$VAL" --home "$FIX/fix-cycles" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" == *fix_cycles_exceeded* ]]
  [[ "$output" == *tkt-203-over* ]]
  [[ "$output" != *tkt-204-ok* ]]
}
