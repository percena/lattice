#!/usr/bin/env bats
# Tests for build-review-context.sh (fixture .lattice home; no network, no gh).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export BRC="$REPO_ROOT/skills/_lattice-lib/scripts/build-review-context.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brc.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN/.lattice/specs" "$MAIN/.lattice/tickets" "$MAIN/docs/adr"
  git -C "$MAIN" init -q -b main
  cd "$MAIN"

  # Stub gh so the fallback path is deterministic and never hits the network.
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "${GH_MODE:-fail}" in
  ok)
    printf 'pr-12 https://github.com/acme/r/pull/12 · found by search\n'
    exit 0
    ;;
  empty)
    exit 0
    ;;
  *)
    echo "boom" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  unset GH_MODE

  cat >"$MAIN/.lattice/specs/spc-9-demo.md" <<'EOF'
---
id: spc-9
slug: demo
title: Demo spec
tickets: [tkt-1, tkt-2]
---

# Spec: Demo

Cites ADR-004 for the reviewer-independence law.
EOF

  mkdir -p "$MAIN/.lattice/tickets/tkt-1-alpha" "$MAIN/.lattice/tickets/tkt-2-beta"
  cat >"$MAIN/.lattice/tickets/tkt-1-alpha/README.md" <<'EOF'
# tkt-1-alpha

| Field | Value |
| --- | --- |
| status | pr-open |
| covers | A1 |
| blocked_by | (none) |
| prs | pr-11 / https://github.com/acme/r/pull/11 |

## Approach

Real approach content.

## Decision journal

- picked X over Y (source: preference DEFAULT)

## Pending decisions

## Attempts

- try 1: failed because Z; next differs by W

## Finish
EOF

  cat >"$MAIN/.lattice/tickets/tkt-2-beta/README.md" <<'EOF'
# tkt-2-beta

| Field | Value |
| --- | --- |
| status | in-progress |
| covers | A2 |
| blocked_by | #1 |
| prs | (none) |

## Approach

<!-- Authored at split time: sketch + touch-set. -->

## Decision journal

<!-- Append-only during execution. Each entry cites its
     resolution source per decision-policy. -->

## Pending decisions

## Attempts

<!-- Fallback ledger. -->

## Finish
EOF

  cat >"$MAIN/docs/adr/004-example.md" <<'EOF'
# ADR 004: Example
EOF
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "spec input resolves tickets from front matter" {
  run bash "$BRC" --spec 9 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"input | spec spc-9"* ]]
  [[ "$output" == *"spc-9-demo.md"* ]]
  [[ "$output" == *"### tkt-1"* ]]
  [[ "$output" == *"### tkt-2"* ]]
  [[ "$output" == *"tkt-1-alpha/README.md"* ]]
  [[ "$output" == *"tkt-2-beta/README.md"* ]]
}

@test "ids input works with bare and prefixed ids" {
  run bash "$BRC" --ids tkt-1 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### tkt-1"* ]]
  [[ "$output" != *"### tkt-2"* ]]

  run bash "$BRC" --ids 1,2 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### tkt-1"* ]]
  [[ "$output" == *"### tkt-2"* ]]
}

@test "missing binder → non-zero, fail loud" {
  run bash "$BRC" --ids 1,3 --home "$MAIN/.lattice"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing binder for tkt-3"* ]]
}

@test "missing spec → non-zero" {
  run bash "$BRC" --spec 99 --home "$MAIN/.lattice"
  [ "$status" -ne 0 ]
  [[ "$output" == *"spc-99 not found"* ]]
}

@test "exactly one input mode required" {
  run bash "$BRC" --home "$MAIN/.lattice"
  [ "$status" -ne 0 ]
  run bash "$BRC" --spec 9 --ids 1 --home "$MAIN/.lattice"
  [ "$status" -ne 0 ]
}

@test "evidence flags: content vs template-comment-only sections" {
  run bash "$BRC" --spec 9 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  # tkt-1 has real content everywhere except Pending decisions
  [[ "$output" == *"approach=present · decision-journal=present · pending-decisions=empty · attempts=present"* ]]
  # tkt-2 sections hold only HTML template comments → empty
  [[ "$output" == *"approach=empty · decision-journal=empty · pending-decisions=empty · attempts=empty"* ]]
  [[ "$output" == *"tkt-2: approach, decision-journal, attempts empty"* ]]
}

@test "ADR citation resolves to docs/adr file" {
  run bash "$BRC" --spec 9 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADR-004"* ]]
  [[ "$output" == *"docs/adr/004-example.md (exists)"* ]]
}

@test "gh fallback failure degrades to a note for (none) prs row" {
  export GH_MODE=fail
  run bash "$BRC" --ids 2 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh query failed — binder row is the only source"* ]]
}

@test "gh fallback success surfaces search hits marked verify-linkage" {
  export GH_MODE=ok
  run bash "$BRC" --ids 2 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prs (gh fallback, verify linkage): pr-12 https://github.com/acme/r/pull/12"* ]]
}

@test "gh fallback empty result is reported as no PR found" {
  export GH_MODE=empty
  run bash "$BRC" --ids 2 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no PR found for #2)"* ]]
}

@test "binder prs row is surfaced without gh" {
  run bash "$BRC" --ids 1 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prs (binder row): pr-11 / https://github.com/acme/r/pull/11"* ]]
}

@test "batch report input extracts ticket set" {
  cat >"$TEST_DIR/report.md" <<'EOF'
# Batch report
| tkt-2 | 0 | ok |
| tkt-1 | 0 | ok |
EOF
  run bash "$BRC" --batch-report "$TEST_DIR/report.md" --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### tkt-1"* ]]
  [[ "$output" == *"### tkt-2"* ]]

  run bash "$BRC" --batch-report "$TEST_DIR/nope.md" --home "$MAIN/.lattice"
  [ "$status" -ne 0 ]
}

# --- --from-heads: binder state read from open PR heads (fixture remote) ------
# A bare repo on a local path stands in for origin; `git fetch` + `git show`
# behave identically to a network remote, so no skip is needed.

setup_from_heads_fixture() {
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" add .
  git -C "$MAIN" commit -qm 'fixture: baseline'
  ORIGIN="$TEST_DIR/origin.git"
  git init -q --bare "$ORIGIN"
  git -C "$MAIN" remote add origin "$ORIGIN"
  git -C "$MAIN" push -q origin main
  # PR head: tkt-2's binder is stamped there (pr-open + journal content)
  git -C "$MAIN" checkout -qb tkt-2-beta-head
  sed -i.bak 's/| status | in-progress |/| status | pr-open |/' \
    "$MAIN/.lattice/tickets/tkt-2-beta/README.md"
  rm -f "$MAIN/.lattice/tickets/tkt-2-beta/README.md.bak"
  sed -i.bak 's#| prs | (none) |#| prs | pr-22 — https://github.com/acme/r/pull/22 |#' \
    "$MAIN/.lattice/tickets/tkt-2-beta/README.md"
  rm -f "$MAIN/.lattice/tickets/tkt-2-beta/README.md.bak"
  printf '\n' >>"$MAIN/.lattice/tickets/tkt-2-beta/README.md"
  python3 - "$MAIN/.lattice/tickets/tkt-2-beta/README.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("## Decision journal", "## Decision journal\n\n- picked A over B (source: ticket AC)", 1)
open(p, "w", encoding="utf-8").write(s)
PY
  git -C "$MAIN" commit -aqm 'fixture: head-stamped binder'
  git -C "$MAIN" push -q origin tkt-2-beta-head
  git -C "$MAIN" checkout -q main
}

@test "--from-heads reads binder state from the open PR head (gh search path)" {
  setup_from_heads_fixture
  # local binder row is (none): PR number comes from the gh search fallback
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr list") printf '22\n' ;;
  "pr view") printf '%s\n' '{"state":"OPEN","headRefName":"tkt-2-beta-head"}' ;;
esac
exit 0
EOF
  chmod +x "$STUB_BIN/gh"
  run bash "$BRC" --ids 2 --home "$MAIN/.lattice" --from-heads
  [ "$status" -eq 0 ]
  [[ "$output" == *"binder source: head:pr-22 (tkt-2-beta-head)"* ]]
  # head state, not the local in-progress/(none) state
  [[ "$output" == *"- status: pr-open"* ]]
  [[ "$output" == *"decision-journal=present"* ]]
  # local file untouched (read-only contract)
  grep -q '| status | in-progress |' "$MAIN/.lattice/tickets/tkt-2-beta/README.md"
}

@test "--from-heads falls back to the local binder when gh cannot resolve a head" {
  setup_from_heads_fixture
  export GH_MODE=fail
  run bash "$BRC" --ids 1 --home "$MAIN/.lattice" --from-heads
  [ "$status" -eq 0 ]
  # tkt-1's binder row names pr-11, but gh pr view fails → local source marked
  [[ "$output" == *"binder source: local ("* ]]
  [[ "$output" == *"- status: pr-open"* ]]
}

@test "--from-heads marks a non-open PR as local source" {
  setup_from_heads_fixture
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") printf '%s\n' '{"state":"MERGED","headRefName":"tkt-1-alpha-head"}' ;;
esac
exit 0
EOF
  chmod +x "$STUB_BIN/gh"
  run bash "$BRC" --ids 1 --home "$MAIN/.lattice" --from-heads
  [ "$status" -eq 0 ]
  [[ "$output" == *"binder source: local (pr-11 is MERGED — not an open head)"* ]]
}

@test "without --from-heads no binder-source line is emitted" {
  run bash "$BRC" --ids 1 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" != *"binder source:"* ]]
}

# tkt-91: the placeholder predicate matches any `(none…)` variant — a
# decorated placeholder must trigger the gh fallback, not read as filled.

@test "decorated (none — …) placeholder still triggers the gh fallback" {
  sed -i.bak 's#| prs | (none) |#| prs | (none — rides tkt-81 PR) |#' \
    "$MAIN/.lattice/tickets/tkt-2-beta/README.md"
  rm -f "$MAIN/.lattice/tickets/tkt-2-beta/README.md.bak"
  export GH_MODE=ok
  run bash "$BRC" --ids 2 --home "$MAIN/.lattice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"prs (binder row): (none — rides tkt-81 PR)"* ]]
  [[ "$output" == *"prs (gh fallback, verify linkage): pr-12 https://github.com/acme/r/pull/12"* ]]
}
