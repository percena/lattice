#!/usr/bin/env bats

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export VAL="$REPO_ROOT/tools/validate-lattice-artifacts.py"
  export FIX="$REPO_ROOT/tools/tests/fixtures/lattice-artifacts"
}

@test "pass fixture is clean" {
  run python3 "$VAL" --home "$FIX/pass" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
}

@test "fail fixture reports invalid status, covers, onesided edge, malformed review id" {
  run python3 "$VAL" --home "$FIX/fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  printf '%s\n' "$output" | grep -qF invalid_ticket_status
  printf '%s\n' "$output" | grep -qF covers_not_on_spec
  printf '%s\n' "$output" | grep -qF onesided_spec_ticket_edge
  printf '%s\n' "$output" | grep -qF malformed_review_id
}

@test "binder field rows come from the first table only; example table cannot shadow" {
  # tkt-9 binder card (first table) has no status row; status comes from the
  # TL;DR. A later docs/example table carrying status/covers rows must not
  # shadow the binder card.
  run python3 "$VAL" --home "$FIX/first-table" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
}

@test "slugless spec filename derives id without the .md extension" {
  # spc-12.md has no front-matter id and no slug; fallback must yield spc-12.
  run python3 "$VAL" --home "$FIX/first-table" --json
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -F malformed_spec_id)" ]
  [ -z "$(printf '%s' "$output" | tr -d '\n' | grep -E 'spc-12\.md.*is not spc-N')" ]
}

@test "bold A-id in prose outside Acceptance is not coverable" {
  # spc-8 mentions **A7** in Notes prose; tkt-8 covers A7 — must fail because
  # only Acceptance-section A-ids are coverable.
  run python3 "$VAL" --home "$FIX/acceptance-scope" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF covers_not_on_spec
  printf '%s\n' "$output" | grep -qF "A7"
}

@test "working FSM states (pr-open) and closed-with-Finish pass clean" {
  run python3 "$VAL" --home "$FIX/status-fsm" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF '"warning_count": 0'
}

@test "unknown status value fails" {
  run python3 "$VAL" --home "$FIX/status-fsm-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF invalid_ticket_status
  printf '%s\n' "$output" | grep -qF "'bogus'"
}

@test "closed without real Finish ledger content fails" {
  run python3 "$VAL" --home "$FIX/status-fsm-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF closed_without_finish
  printf '%s\n' "$output" | grep -qF tkt-63-closed-empty
}

@test "legacy open warns but passes (lazy migration)" {
  run python3 "$VAL" --home "$FIX/status-legacy-open" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF legacy_open_status
  printf '%s\n' "$output" | grep -qF '"warning_count": 1'
}

@test "header Status copy contradicting the field table warns (does not fail)" {
  # tkt-70: header in-progress vs table queued → exactly one warning; the home
  # still passes (warnings never fail the run).
  run python3 "$VAL" --home "$FIX/header-status" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF header_status_mismatch
  printf '%s\n' "$output" | grep -qF tkt-70-mismatch
  printf '%s\n' "$output" | grep -qF '"warning_count": 1'
}

@test "matching, legacy-open, and prose-mention headers do not warn" {
  # tkt-71 header==table, tkt-72 legacy-coarse open header (exempt), tkt-73
  # prose mention of **Status:** below the binder card — none may fire.
  run python3 "$VAL" --home "$FIX/header-status" --json
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-71-match)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-72-legacy-header)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-73-prose-mention)" ]
}

@test "malformed filled prs row warns (does not fail)" {
  # tkt-80: legacy `URL · pr-N — URL` shape → exactly one warning; the home
  # still passes (warning-level permanently — adopt flows may reintroduce
  # legacy rows).
  run python3 "$VAL" --home "$FIX/prs-row" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF prs_row_format
  printf '%s\n' "$output" | grep -qF tkt-80-malformed
  printf '%s\n' "$output" | grep -qF '"warning_count": 1'
}

@test "canonical, comma-separated multi-PR, and placeholder prs rows are silent" {
  # tkt-81 `pr-81 — URL`, tkt-83 `pr-83 — URL, pr-84 — URL`, tkt-82
  # `(none — rides tkt-81 PR)` placeholder — none may fire.
  run python3 "$VAL" --home "$FIX/prs-row" --json
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-81-canonical)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-82-placeholder)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-83-multi)" ]
}

@test "prose backtick mention must not mask onesided_spec_ticket_edge" {
  # spec spc-4 omits tkt-4 from authoritative `tickets:` but mentions `tkt-4`
  # in prose; the one-sided edge must still fire.
  run python3 "$VAL" --home "$FIX/onesided-prose" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  printf '%s' "$output" | tr -d '\n' | grep -qE 'onesided_spec_ticket_edge.*tkt-4.*spc-4'
}

# tkt-90: inverse coherence — a merged OR cancel ## Finish ledger requires
# terminal status (tkt-151 A4 extended this to cancel ledgers: an
# `issue #N closed:` stamp without a merge is also terminal evidence).

@test "merged Finish ledger with working status fails; cancel ledger with closed status is clean" {
  run python3 "$VAL" --home "$FIX/finish-status-mismatch" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF finish_without_terminal_status
  printf '%s\n' "$output" | grep -qF tkt-70-merged-but-pr-open
  # tkt-71 carries a cancel ledger (`issue #71 closed:`) but its status IS
  # closed, so no finding fires for it.
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-71-cancel-ok)" ]
}

@test "two binder dirs claiming one tkt id fail with duplicate_ticket_id" {
  run python3 "$VAL" --home "$FIX/dup-ticket-id" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF duplicate_ticket_id
  printf '%s\n' "$output" | grep -qF tkt-3-first
  printf '%s\n' "$output" | grep -qF tkt-3-second
}

# spc-104 A1: feature-map format + status vocabulary (checked when the file exists).

@test "well-formed feature map passes clean" {
  # LATTICE_EVIDENCE_FRESHNESS_DAYS bumped so the static fixture's last-verified
  # date never goes stale (spc-270 A5.2 freshness is exercised by the fault fixture).
  run env LATTICE_EVIDENCE_FRESHNESS_DAYS=36500 python3 "$VAL" --home "$FIX/feature-map" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"warning_count": 0'
}

@test "feature map: unknown status errors, empty oracle warns" {
  run python3 "$VAL" --home "$FIX/feature-map-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF feature_map_status
  printf '%s\n' "$output" | grep -qF "'verified'"
  printf '%s\n' "$output" | grep -qF feature_map_row_format
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
  printf '%s\n' "$output" | grep -qF '"ok": true'
  [ -z "$(printf '%s\n' "$output" | grep -F invalid_ticket_status)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-200)" ]
}

@test "finish ledger exempts the whole (none…) placeholder family" {
  # tkt-201: status closed, ## Finish carries "(none — rides tkt-5 PR)" — a
  # placeholder (PRS_PLACEHOLDER_RE), not the literal "(none yet)". The family
  # is exempt, so has_finish_ledger returns False and closed_without_finish fires.
  run python3 "$VAL" --home "$FIX/finish-placeholder-family" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF closed_without_finish
  printf '%s\n' "$output" | grep -qF tkt-201-placeholder
}

@test "A-ids inline on the Acceptance heading line are coverable" {
  # spc-202 declares "## Acceptance — **A1**, **A2**"; tkt-202 covers A1.
  # Heading-line A-ids must register, so covers_not_on_spec must NOT fire.
  run python3 "$VAL" --home "$FIX/acceptance-heading-aids" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  [ -z "$(printf '%s\n' "$output" | grep -F covers_not_on_spec)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-202)" ]
}

# tkt-123: bounded-loop invariant — fix_cycles field-table row + cap (>2 warns).

@test "fix_cycles >2 warns (bounded-loop cap); ≤2 and missing are clean" {
  # tkt-203 has fix_cycles 3 → fix_cycles_exceeded warning (run still passes —
  # warning level). tkt-204 has fix_cycles 2 → no warning.
  run python3 "$VAL" --home "$FIX/fix-cycles" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF fix_cycles_exceeded
  printf '%s\n' "$output" | grep -qF tkt-203-over
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-204-ok)" ]
}

# tkt-155: binder-dir-N vs github-field-N desync — phantom binders and mismatches.

# spc-186 A4 / tkt-191: binder created/updated timestamps — missing warns
# (lazy migration), malformed errors, well-formed is clean.

@test "binder created/updated well-formed rows are clean (zero warnings)" {
  run python3 "$VAL" --home "$FIX/timestamps-clean" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF '"warning_count": 0'
  [ -z "$(printf '%s\n' "$output" | grep -F missing_binder_timestamp)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F malformed_binder_timestamp)" ]
}

@test "binder missing created/updated warns (lazy migration, exit 0)" {
  run python3 "$VAL" --home "$FIX/timestamps-missing" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF missing_binder_timestamp
  printf '%s\n' "$output" | grep -qF 'created, updated'
  [ -z "$(printf '%s\n' "$output" | grep -F malformed_binder_timestamp)" ]
}

@test "binder malformed created/updated errors (not a warning)" {
  run python3 "$VAL" --home "$FIX/timestamps-malformed" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  printf '%s\n' "$output" | grep -qF malformed_binder_timestamp
  printf '%s\n' "$output" | grep -qF "created"
  printf '%s\n' "$output" | grep -qF "updated"
}

@test "matching github URL and dir N pass clean" {
  # tkt-205-match: github issue #205, dir tkt-205 → no finding.
  run python3 "$VAL" --home "$FIX/github-field-clean" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-205-match)" ]
}

@test "dir N vs github issue N mismatch errors" {
  # tkt-206-mismatch: dir tkt-206 but github issue #888 → error.
  run python3 "$VAL" --home "$FIX/github-field-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF binder_dir_github_mismatch
  printf '%s\n' "$output" | grep -qF tkt-206
  printf '%s\n' "$output" | grep -qF 888
}

@test "numeric dir with placeholder github warns phantom_binder_smell" {
  # tkt-207-phantom: numeric dir tkt-207, github "(to be created)" →
  # phantom_binder_smell warning (run passes — warning level).
  run python3 "$VAL" --home "$FIX/github-field-warn" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF phantom_binder_smell
  printf '%s\n' "$output" | grep -qF tkt-207-phantom
}

@test "github URL that is not an issues path warns binder_github_malformed" {
  # tkt-208-pending-url: github value is a /pull/ URL, not /issues/ →
  # binder_github_malformed warning (run passes — warning level).
  run python3 "$VAL" --home "$FIX/github-field-warn" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF binder_github_malformed
  printf '%s\n' "$output" | grep -qF tkt-208-pending-url
}

# tkt-151: Spec/Review/coupled-ticket/Finish-evidence state invariants.

@test "spec done with open non-deferred acceptance fails" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF spec_done_open_acceptance
  printf '%s\n' "$output" | grep -qF spc-10-done-open
}

@test "unknown spec status fails" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF invalid_spec_status
  printf '%s\n' "$output" | grep -qF "'bogus'"
  printf '%s\n' "$output" | grep -qF spc-11-bad-status
}

@test "superseded spec without a valid link fails" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF spec_superseded_no_link
  printf '%s\n' "$output" | grep -qF spc-12-superseded-nolink
}

@test "terminal spec with contradictory display status fails (not warns)" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF spec_header_status_mismatch
  printf '%s\n' "$output" | grep -qF spc-13-done-stale-header
  # Error-level (terminal), not a warning — the home fails.
  printf '%s\n' "$output" | grep -qF '"ok": false'
}

@test "unknown review status and outcome fail" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF invalid_review_status
  printf '%s\n' "$output" | grep -qF "'bogus'"
  printf '%s\n' "$output" | grep -qF rev-bad-status
  printf '%s\n' "$output" | grep -qF invalid_review_outcome
  printf '%s\n' "$output" | grep -qF rev-bad-outcome
}

@test "concluded review without exactly one valid outcome fails" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF concluded_review_no_outcome
  printf '%s\n' "$output" | grep -qF rev-no-outcome
}

@test "stuck without a valid wait_reason fails (missing and contradictory)" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF stuck_without_valid_wait_reason
  printf '%s\n' "$output" | grep -qF tkt-50-stuck-noreason
  # Contradictory: stuck + a deferred reason (fuse-halt) must also fail.
  printf '%s\n' "$output" | grep -qF tkt-52-stuck-contradictory
  printf '%s\n' "$output" | grep -qF 'fuse-halt'
}

@test "deferred without a valid reason fails" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF deferred_without_valid_reason
  printf '%s\n' "$output" | grep -qF tkt-51-deferred-noreason
}

@test "cancel Finish ledger with non-terminal status fails (A4)" {
  run python3 "$VAL" --home "$FIX/spec-state-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF finish_without_terminal_status
  printf '%s\n' "$output" | grep -qF tkt-53-cancel-open
}

@test "spec-state pass home: done/deferred/superseded/locked, concluded reviews, coupled fields all clean" {
  run python3 "$VAL" --home "$FIX/spec-state-pass" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF '"warning_count": 0'
  [ -z "$(printf '%s\n' "$output" | grep -F spec_done_open_acceptance)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F spec_header_status_mismatch)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F spec_superseded_no_link)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F invalid_review)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F concluded_review_no_outcome)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F stuck_without_valid_wait_reason)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F deferred_without_valid_reason)" ]
  [ -z "$(printf '%s\n' "$output" | grep -F finish_without_terminal_status)" ]
}

# tkt-174: tkt-pending-<slug> dirs are a valid transient state — not malformed.

@test "tkt-pending dir with placeholder github warns binder_github_pending (no error)" {
  # tkt-pending-noissue: dir is tkt-pending-noissue, github "(to be created)"
  # → binder_github_pending warning only (no malformed_ticket_id error).
  run python3 "$VAL" --home "$FIX/github-field-warn" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF binder_github_pending
  printf '%s\n' "$output" | grep -qF tkt-pending-noissue
  [ -z "$(printf '%s' "$output" | tr -d '\n' | grep -E 'malformed_ticket_id.*tkt-pending-noissue')" ]
}

# tkt-179: post-merge review fixes — validator improvements.

@test "A4: no-issue cancel binder with working status fails (finish_without_terminal_status)" {
  # tkt-54-cancel-no-issue: status queued, Finish has `- cancelled:` line.
  # The new FINISH_CANCELLED_RE recognizes `- cancelled:` as terminal evidence,
  # so finish_without_terminal_status must fire.
  run python3 "$VAL" --home "$FIX/tkt-179-fixes" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF finish_without_terminal_status
  printf '%s\n' "$output" | grep -qF tkt-54-cancel-no-issue
}

@test "A5: concluded review with invalid outcome fires exactly one finding (no double)" {
  # rev-concluded-bad-outcome: status concluded, outcome bogus.
  # invalid_review_outcome fires; concluded_review_no_outcome must NOT also fire
  # (the fix narrowed the condition to `not rv_out` only).
  run python3 "$VAL" --home "$FIX/tkt-179-fixes" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF invalid_review_outcome
  printf '%s\n' "$output" | grep -qF rev-concluded-bad-outcome
  # Count occurrences of concluded_review_no_outcome — must be zero
  nocount=$(echo "$output" | grep -c 'concluded_review_no_outcome' || true)
  [ "$nocount" -eq 0 ]
}

@test "A6: spec_status is scoped to front matter — body prose status: line is ignored" {
  # spc-14-body-status: no front matter, body has a line `status: bogus`.
  # The old full-text regex would match it → invalid_spec_status; the new
  # parse_front_matter scoping returns None → no status check fires.
  run python3 "$VAL" --home "$FIX/tkt-179-fixes" --json
  [ -z "$(printf '%s' "$output" | tr -d '\n' | grep -E 'invalid_spec_status.*spc-14')" ]
}

# tkt-238: post-merge dev→main review — terminal-state/drift detection fixes.
# H1: prose mentioning `merged:`/`closed:` must NOT fire finish_without_terminal_status;
#     a real anchored stamp still does (covered by finish-status-mismatch/tkt-70).
# M2: an indented `- cancelled:` bullet IS terminal evidence and must fire.
# M3: `~~` wrapping unrelated prose does NOT defer an open A-id; a struck A-id does.

@test "tkt-238 H1: Finish prose mentioning merged:/closed: does not fire finish_without_terminal_status" {
  # tkt-238-prose-merged: status pr-open, ## Finish has a note line
  # `- note: PR was merged: … but reverted` and a placeholder
  # `- (none — not yet merged: waiting on CI)`. Neither is a canonical stamp,
  # so finish_ledger_terminal returns False and no finding fires — the binder
  # passes clean (a reverted-and-reopened PR is a real scenario the ledger
  # grammar cannot express).
  run python3 "$VAL" --home "$FIX/finish-prose-mention" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  [ -z "$(printf '%s\n' "$output" | grep -F finish_without_terminal_status)" ]
}

@test "tkt-238 M2: indented - cancelled: bullet fires finish_without_terminal_status" {
  # tkt-238-indented-cancel: status pr-open, ## Finish has an indented
  # `  - cancelled: wontfix` bullet. The anchored `^\s*-\s+cancelled:` regex
  # detects indented cancels as terminal evidence, so the non-terminal status
  # contradicts a cancel ledger and finish_without_terminal_status fires.
  run python3 "$VAL" --home "$FIX/finish-indented-cancel" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF finish_without_terminal_status
  printf '%s\n' "$output" | grep -qF tkt-238-indented-cancel
}

@test "tkt-238 M3: done spec with ~~ around prose (not the A-id) fires spec_done_open_acceptance" {
  # spc-238-done-strikethrough-open: status done, acceptance has
  # `- [ ] **A2** ~~deprecated sub-approach~~ — actually still open`. The `~~`
  # wraps unrelated prose, not the A-id, so A2 is open and non-deferred →
  # spec_done_open_acceptance fires (the old `"~~" in line` heuristic masked it).
  run python3 "$VAL" --home "$FIX/spec-done-strikethrough-open" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF spec_done_open_acceptance
  printf '%s\n' "$output" | grep -qF spc-238-done-strikethrough-open
}

@test "tkt-238 M3 inverse: a struck-through A-id (~~**A3**~~) is deferred, not open" {
  # spc-24-done-struck-aid lives in the spec-state-pass home: status done,
  # acceptance has `- [ ] ~~**A3**~~ deprecated sub-approach`. The A-id itself
  # is struck, so it is deferred and must NOT trip spec_done_open_acceptance —
  # the whole home stays clean.
  run python3 "$VAL" --home "$FIX/spec-state-pass" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  [ -z "$(printf '%s\n' "$output" | grep -F spec_done_open_acceptance)" ]
}

# tkt-259 / spc-254 A7: evidence proof for `pass` feature-map rows. A pass row
# must prove: story path exists, story header oracle/mutations consistent, a
# status=pass result JSON exists. A destructive story needs an authorization
# trace. Each fault is injected in one row of the evidence-proof-fail home; the
# ftr-clean row is the control (no finding).

@test "A7: pass row with no story path fails (evidence_proof_no_story)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  printf '%s\n' "$output" | grep -qF evidence_proof_no_story
  printf '%s\n' "$output" | grep -qF ftr-no-story
}

@test "A7: pass row with missing story file fails (evidence_proof_story_missing)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF evidence_proof_story_missing
  printf '%s\n' "$output" | grep -qF ftr-missing-story
}

@test "A7: pass row with mutations mismatch fails (evidence_proof_mutations_mismatch)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF evidence_proof_mutations_mismatch
  printf '%s\n' "$output" | grep -qF mut.story.md
}

@test "A7: pass row with oracle mismatch fails (evidence_proof_oracle_mismatch)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF evidence_proof_oracle_mismatch
  printf '%s\n' "$output" | grep -qF spc-99
}

@test "A7: pass row with no result JSON fails (evidence_proof_no_result)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF evidence_proof_no_result
  printf '%s\n' "$output" | grep -qF ftr-no-result
}

@test "A7: pass row with result JSON not pass fails (evidence_proof_result_not_pass)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF evidence_proof_result_not_pass
  printf '%s\n' "$output" | grep -qF notpass.result.json
}

@test "A7: destructive pass row without authorization trace fails (evidence_proof_destructive_no_auth)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF evidence_proof_destructive_no_auth
  printf '%s\n' "$output" | grep -qF destructive.story.md
}

@test "A7: a fully-proven pass row fires no evidence-proof finding (control)" {
  run python3 "$VAL" --home "$FIX/evidence-proof-fail" --json
  [ "$status" -eq 1 ]   # other rows fail; the control row itself is clean
  [ -z "$(printf '%s\n' "$output" | grep -F 'evidence_proof' | grep -F clean)" ]
}

# tkt-259 / spc-254 A7: done-Spec PR union. A `done` Spec's front-matter `prs`
# must contain the union of its child binders' prs rows. Warning-level during
# the D3 migration window (ratcheted via the warning baseline).

@test "A7: done Spec missing a child binder PR warns spec_prs_missing_child_union" {
  # spc-900 (done, prs []) but tkt-900 binder lists pr-900 → warning. spc-901
  # (done, prs [pr-901]) with tkt-901 binder pr-901 is the clean control.
  run python3 "$VAL" --home "$FIX/spec-prs-union" --json
  [ "$status" -eq 0 ]   # warning-level; run still passes
  printf '%s\n' "$output" | grep -qF spec_prs_missing_child_union
  printf '%s\n' "$output" | grep -qF spc-900
  printf '%s\n' "$output" | grep -qF pr-900
  [ -z "$(printf '%s\n' "$output" | grep -F 'spec_prs_missing_child_union' | grep -F spc-901)" ]
}

# tkt-259 / spc-254 A8: warning baseline + one-way ratchet. Warnings in the
# baseline pass; new (non-baselined) warnings fail the run separately.

@test "A8: a baselined warning passes (ratchet clean)" {
  # Full baseline covers both legacy_open_status warnings → 0 new → exit 0.
  run python3 "$VAL" --home "$FIX/ratchet" --baseline "$FIX/ratchet/baseline-full.txt" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF '"new_warning_count": 0'
  printf '%s\n' "$output" | grep -qF '"warning_count": 2'
}

@test "A8: a new (non-baselined) warning fails the run (ratchet)" {
  # Partial baseline covers tkt-301 only; tkt-302 is new → exit 1.
  run python3 "$VAL" --home "$FIX/ratchet" --baseline "$FIX/ratchet/baseline-partial.txt" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  printf '%s\n' "$output" | grep -qF '"new_warning_count": 1'
  printf '%s\n' "$output" | grep -qF ratchet_new_warnings
}


# --- spc-270 A5: versioned runtime evidence (tkt-274) ---

@test "A5: v1 evidence (identity+freshness+assertions+screenshot+leftovers) is clean" {
  run env LATTICE_EVIDENCE_FRESHNESS_DAYS=36500 python3 "$VAL" --home "$FIX/evidence-v1" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
}

@test "A5.5: v0 legacy evidence warns (lazy migration, not error)" {
  run python3 "$VAL" --home "$FIX/evidence-v0" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF evidence_legacy_v0
}

@test "A5.4: v1 fault fixture reports identity mismatch, stale run, no/failed assertions, missing screenshot, undeclared leftovers" {
  run python3 "$VAL" --home "$FIX/evidence-v1-fail" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  printf '%s\n' "$output" | grep -qF evidence_v1_identity_mismatch
  printf '%s\n' "$output" | grep -qF evidence_stale_run
  printf '%s\n' "$output" | grep -qF evidence_no_assertions
  printf '%s\n' "$output" | grep -qF evidence_failed_assertion
  printf '%s\n' "$output" | grep -qF evidence_screenshot_missing
  printf '%s\n' "$output" | grep -qF evidence_leftovers_undeclared
  printf '%s\n' "$output" | grep -qF evidence_v1_identity_missing
  printf '%s\n' "$output" | grep -qF evidence_v1_run_id_missing
  printf '%s\n' "$output" | grep -qF evidence_v1_result_schema_missing
}

# --- spc-270 A6: true warning ratchet (tkt-276) ---

@test "A6.2: missing baseline (--baseline <nonexistent>) fails closed (ratchet mode)" {
  # A configured-but-missing baseline must NOT silently pass — fail closed.
  run python3 "$VAL" --home "$FIX/ratchet" --baseline "$FIX/ratchet/DOES-NOT-EXIST.txt"
  [ "$status" -eq 1 ]
}

@test "A6.2: corrupt/malformed baseline fails closed (ratchet mode)" {
  run python3 "$VAL" --home "$FIX/ratchet" --baseline "$FIX/ratchet/corrupt.txt"
  [ "$status" -eq 1 ]
}

@test "A6.1: two same-code+path findings with different details are DISTINCT new_warnings (real validator)" {
  # ratchet-distinct fixture: 2 malformed feature-map rows → 2 feature_map_row_format
  # findings at the SAME path with DIFFERENT line numbers. With a dummy baseline
  # (activates ratchet, matches neither), BOTH must be new_warnings with DISTINCT
  # signatures (no set-collapse — the A6.1 goal). Exercises the REAL validator.
  run python3 "$VAL" --home "$FIX/ratchet-distinct" --baseline "$FIX/ratchet/dummy.txt" --json
  [ "$status" -eq 1 ]
  out=$(printf '%s\n' "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
nw=d.get('ratchet_new_warnings',[])
fm=[w for w in nw if w.get('code')=='feature_map_row_format']
assert len(fm)==2, 'expected 2 feature_map new_warnings, got %d' % len(fm)
sigs={w.get('detail','') for w in fm}
assert len(sigs)==2, '2 findings collapsed to %d sig (A6.1 regression)' % len(sigs)
print('A6.1: 2 distinct new_warnings (real validator)')
")
  [ -n "$out" ]
}

@test "A6.2: a valid present 3-column baseline does NOT false fail-closed (no warnings → pass)" {
  # A non-corrupt baseline + a fixture with zero warnings must pass (fail-closed
  # only on missing/corrupt, not on a present valid baseline).
  run python3 "$VAL" --home "$FIX/ratchet-clean" --baseline "$FIX/ratchet/valid-3col.txt"
  [ "$status" -eq 0 ]
}

@test "A6.4: non-numeric --migration-version exits 2 (usage error, not a findings crash)" {
  run python3 "$VAL" --migration-version next --home "$FIX/pass"
  [ "$status" -eq 2 ]
}

# --- spc-337 A1 / ADR-012 sec.4: ledger coverage --------------------------

@test "spc-337 A1: terminal binder without a ledger is an error post-cutoff, a legacy warning before/undated, clean with a ledger" {
  run python3 "$VAL" --home "$FIX/ledger-coverage" --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  # post-cutoff (created 2026-09-05) -> error code closed_without_ledger
  printf '%s' "$output" | tr -d '\n' | grep -qE '"code": "closed_without_ledger",[^}]*"path": "[^"]*tkt-1-post-cutoff-no-ledger'
  # pre-cutoff + undated -> closed_without_ledger_legacy (warning)
  printf '%s' "$output" | tr -d '\n' | grep -qE '"code": "closed_without_ledger_legacy",[^}]*"level": "warning",[^}]*"path": "[^"]*tkt-2-pre-cutoff-no-ledger'
  printf '%s' "$output" | tr -d '\n' | grep -qE '"code": "closed_without_ledger_legacy",[^}]*"level": "warning",[^}]*"path": "[^"]*tkt-3-undated-no-ledger'
  # with a ledger -> no coverage finding at all
  [ -z "$(printf '%s\n' "$output" | grep -F tkt-4-with-ledger)" ]
  printf '%s\n' "$output" | grep -qF '"count": 1'
}

# --- tkt-381: binder field-table rows with a stray 3rd column -------------

@test "tkt-381: binder row with a stray 3rd column warns binder_row_extra_columns" {
  # tkt-74-extra-col: status row carries a 3rd column (`| status | queued | 2026-… |`).
  # Warning-level (15 legacy binders carry these; baselined, not re-rowed here).
  run python3 "$VAL" --home "$FIX/extra-columns" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF binder_row_extra_columns
  printf '%s\n' "$output" | grep -qF tkt-74-extra-col
}

@test "spc-337 A2: the any->closed wildcard is gone from the vendored table; explicit terminal edges replay clean" {
  run python3 - "$VAL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('validator', sys.argv[1])
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)
assert ("any", "closed") not in v.LEGAL_TRANSITIONS
for frm in ("queued", "in-progress", "parked", "stuck", "rework", "deferred", "pr-open", "open"):
    assert (frm, "closed") in v.LEGAL_TRANSITIONS, frm
assert not any(e[0] == "any" for e in v.LEGAL_EDGES_FULL)
PY
  [ "$status" -eq 0 ]
  # the fixture ledger (pr-open -> closed) + the coverage fixture replay without illegal_transition_edge
  run python3 "$VAL" --home "$FIX/ledger-coverage" --json
  [ -z "$(printf '%s\n' "$output" | grep -F illegal_transition_edge)" ]
}
