#!/usr/bin/env bats
# Tests for alignment-check.sh Acceptance HARD gates (stubbed gh, no network).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export ALIGN="$REPO_ROOT/skills/finish-work/scripts/alignment-check.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/align-check.XXXXXX")"
  STUB_BIN="$TEST_DIR/bin"
  LATTICE="$TEST_DIR/lattice"
  mkdir -p "$STUB_BIN" "$LATTICE/tickets"
  export LATTICE_HOME="$LATTICE"
  export GH_PR_JSON="$TEST_DIR/pr.json"
  export GH_ISSUE_JSON="$TEST_DIR/issue.json"
  export GH_CALL_LOG="$TEST_DIR/gh-calls.log"

  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${GH_CALL_LOG:-/dev/null}"
# alignment-check invokes: gh pr view N --json ...  /  gh issue view N --json ...
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  cat "${GH_PR_JSON:?}"
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  cat "${GH_ISSUE_JSON:?}"
  exit 0
fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_pr() {
  # $1 body  $2 optional headRefName
  local body="$1"
  local head="${2:-feat/tkt-99-demo}"
  python3 - "$body" "$head" <<'PY' >"$GH_PR_JSON"
import json, sys
body, head = sys.argv[1], sys.argv[2]
json.dump({
  "number": 99,
  "title": "feat: demo land",
  "body": body,
  "state": "OPEN",
  "headRefName": head,
  "baseRefName": "dev",
  "url": "https://example.test/pr/99",
  "isDraft": False,
  "mergeable": "MERGEABLE",
}, sys.stdout)
PY
}

write_issue() {
  # $1 body
  python3 - "$1" <<'PY' >"$GH_ISSUE_JSON"
import json, sys
json.dump({
  "number": 26,
  "title": "demo ticket",
  "body": sys.argv[1],
  "state": "OPEN",
  "labels": [],
}, sys.stdout)
PY
}

write_binder() {
  # $1 body (full README or acceptance fragment)
  local dir="$LATTICE/tickets/tkt-26-demo"
  mkdir -p "$dir"
  cat >"$dir/README.md" <<EOF
# tkt-26-demo

| Field | Value |
| --- | --- |
| status | open |

## Acceptance (this slice)

$1
EOF
}

@test "HARD: Fixes issue with open Acceptance boxes" {
  write_pr $'## Why\n\nShip demo.\n\n## Links\n\n- Fixes #26\n'
  write_issue $'### Acceptance\n- [ ] **A1** first\n- [ ] **A2** second\n'
  write_binder $'- [x] **A1** first\n- [x] **A2** second\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
  printf '%s\n' "$output" | grep -qF "issue #26 has 2 open Acceptance"
}

@test "HARD: binder open boxes on Fixes land" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n- [x] **A2** second\n'
  write_binder $'- [ ] **A1** first\n- [ ] **A2** second\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "binder tkt-26 has 2 open Acceptance"
}

@test "HARD: binder checked but issue still open (GH out of sync)" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  # Issue has open A2; binder has A2 checked → sync gap (also issue open boxes HARD)
  write_issue $'### Acceptance\n- [x] **A1** first\n- [ ] **A2** second\n'
  write_binder $'- [x] **A1** first\n- [x] **A2** second\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qE 'not\ synced\ with\ binder|open\ Acceptance'
}

@test "ok: all Acceptance checked on issue + binder" {
  write_pr $'## Why\n\nShip demo with enough body text.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n- [x] **A2** second\n'
  write_binder $'- [x] **A1** first\n- [x] **A2** second\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "checklist_ok"
}

@test "ok: deferred open boxes are not HARD" {
  write_pr $'## Why\n\nShip demo with enough body text.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** done\n- [ ] **A2** later <!-- deferred: #42 -->\n- [ ] **A3** cut — out-of-scope\n'
  write_binder $'- [x] **A1** done\n- [ ] **A2** later <!-- deferred: #42 -->\n- [ ] **A3** cut — out-of-scope\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'deferred|checklist_ok'
}

@test "Refs only: open Acceptance is WARN not HARD" {
  write_pr $'## Why\n\nRelated work with enough body text.\n\nRefs #26\n'
  write_issue $'### Acceptance\n- [ ] **A1** still open\n'
  write_binder $'- [ ] **A1** still open\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'WARN|Refs'
  [ -z "$(printf '%s\n' "$output" | grep -F "issue #26 has 1 open Acceptance item(s) while PR Fixes")" ]
}

@test "json includes closing_ids" {
  write_pr $'## Why\n\nShip demo with enough body text.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** ok\n'
  write_binder $'- [x] **A1** ok\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE" --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids"'
  printf '%s\n' "$output" | grep -qE '"ok":\ true|"ok":\ true'
}

@test "light profile: open Acceptance on Fixes is WARN (exit 0)" {
  write_pr $'## Why\n\nShip demo.\n\n## Links\n\n- Fixes #26\n'
  write_issue $'### Acceptance\n- [ ] **A1** first\n- [ ] **A2** second\n'
  write_binder $'- [ ] **A1** first\n- [ ] **A2** second\n'
  export LATTICE_PROFILE=light

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "profile: light" || printf '%s\n' "$output" | grep -qF "profile=light"
  printf '%s\n' "$output" | grep -qF "WARN" || printf '%s\n' "$output" | grep -qF "open Acceptance"
  # Must not be HARD-failed
  [ -z "$(printf '%s\n' "$output" | grep -F "alignment: HARD gaps")" ]
}

@test "strict default: open Acceptance on Fixes still HARD" {
  write_pr $'## Why\n\nShip demo.\n\n## Links\n\n- Fixes #26\n'
  write_issue $'### Acceptance\n- [ ] **A1** first\n'
  write_binder $'- [ ] **A1** first\n'
  unset LATTICE_PROFILE

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
}

@test "HARD: indented Acceptance boxes are still open" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n  - [ ] **A1** nested\n    * [ ] **A2** deeper\n'
  write_binder $'- [x] **A1** nested\n- [x] **A2** deeper\n'

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
  printf '%s\n' "$output" | grep -qF "issue #26 has"
}

@test "finds closed binder under tickets/archive" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  # binder only in archive, with open box → HARD
  mkdir -p "$LATTICE/tickets/archive/tkt-26-demo"
  cat >"$LATTICE/tickets/archive/tkt-26-demo/README.md" <<EOF
# tkt-26-demo

| Field | Value |
| --- | --- |
| status | closed |

## Acceptance (this slice)

- [ ] **A1** first
EOF

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "binder tkt-26 has 1 open Acceptance"
}

@test "HARD: Spec cited but Spec file missing (strict land-time)" {
  write_pr $'## Why\n\nShip demo with enough body text.\n\n- Fixes #26\n- Spec: spc-99\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  unset LATTICE_PROFILE

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
  printf '%s\n' "$output" | grep -qF "spc-99"
  printf '%s\n' "$output" | grep -qE 'no\ file|land\-time\ Spec\ load\ failed'
}

@test "ok: bare spc-N in prose is not a Spec cite (no missing-file HARD)" {
  # ADR-019 / create-pr: normative cite is `Spec: spc-N`. Prose mentioning
  # another workstream must not trigger land-time Spec load HARD.
  write_pr $'## Why\n\nShip demo with enough body text about spc-99 residual work.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  unset LATTICE_PROFILE

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "checklist_ok"
  [ -z "$(printf '%s\n' "$output" | grep -F "HARD gaps")" ]
  [ -z "$(printf '%s\n' "$output" | grep -F "land-time Spec load failed")" ]
  printf '%s\n' "$output" | grep -qE 'specs:\ \(none\)|specs:\ \[\]'
}

@test "light profile: missing Spec file is WARN (exit 0)" {
  write_pr $'## Why\n\nShip demo with enough body text.\n\n- Fixes #26\n- Spec: spc-99\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  export LATTICE_PROFILE=light

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "WARN"
  printf '%s\n' "$output" | grep -qF "spc-99"
  [ -z "$(printf '%s\n' "$output" | grep -F "alignment: HARD gaps")" ]
}

@test "WARN: binder covers A* not on Spec Acceptance" {
  write_pr $'## Why\n\nShip demo with enough body text.\n\n- Fixes #26\n- Spec: spc-50\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  mkdir -p "$LATTICE/specs" "$LATTICE/tickets/tkt-26-demo"
  cat >"$LATTICE/specs/spc-50-demo.md" <<'EOF'
---
id: spc-50
tickets:
  - tkt-26
---
# Spec

## Acceptance

- [ ] **A1** only this
EOF
  cat >"$LATTICE/tickets/tkt-26-demo/README.md" <<'EOF'
---
covers: A1, A9
---
# tkt-26

## Acceptance

- [x] **A1** first
EOF

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "WARN"
  printf '%s\n' "$output" | grep -qF "covers"
  printf '%s\n' "$output" | grep -qF "A9"
}

@test "WARN: Spec tickets listed but PR has no Fixes" {
  write_pr $'## Why\n\nSpec-only note with enough body text for length.\n\n- Spec: spc-50\n- Refs #26\n'
  write_issue $'### Acceptance\n- [ ] **A1** open ok for Refs\n'
  mkdir -p "$LATTICE/specs" "$LATTICE/tickets/tkt-26-demo"
  cat >"$LATTICE/specs/spc-50-demo.md" <<'EOF'
---
id: spc-50
tickets:
  - tkt-26
---
# Spec

## Acceptance

- [ ] **A1** item
EOF
  cat >"$LATTICE/tickets/tkt-26-demo/README.md" <<'EOF'
---
covers: A1
---
# tkt-26

## Acceptance

- [ ] **A1** open
EOF

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "WARN"
  printf '%s\n' "$output" | grep -qE 'no\ Fixes/Closes/Resolves|lists\ tickets'
}

@test "adopted: open issue boxes are not HARD when binder Acceptance done" {
  write_pr $'## Why\n\nShip adopted ticket with enough body text.\n\nFixes #26\n'
  # Hand-created issue still has open checkboxes — must not HARD when adopted binder is done
  write_issue $'### Acceptance\n- [ ] **A1** first\n- [ ] **A2** second\n'
  mkdir -p "$LATTICE/tickets/tkt-26-demo"
  cat >"$LATTICE/tickets/tkt-26-demo/README.md" <<'EOF'
# tkt-26-demo

| Field | Value |
| --- | --- |
| status | open |
| adopted | true |

## Acceptance (this slice)

- [x] **A1** first
- [x] **A2** second
EOF
  unset LATTICE_PROFILE

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'checklist_ok|adopted'
  [ -z "$(printf '%s\n' "$output" | grep -F "alignment: HARD gaps")" ]
  [ -z "$(printf '%s\n' "$output" | grep -F "not synced with binder")" ]
}

@test "adopted: open binder boxes still HARD on Fixes land" {
  write_pr $'## Why\n\nShip adopted ticket with enough body text.\n\nFixes #26\n'
  write_issue $'Operator prose only — no lattice checkboxes.\n'
  mkdir -p "$LATTICE/tickets/tkt-26-demo"
  cat >"$LATTICE/tickets/tkt-26-demo/README.md" <<'EOF'
# tkt-26-demo

| Field | Value |
| --- | --- |
| status | open |
| adopted | true |

## Acceptance (this slice)

- [ ] **A1** first
- [ ] **A2** second
EOF
  unset LATTICE_PROFILE

  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
  printf '%s\n' "$output" | grep -qF "binder tkt-26 has"
}


@test "fenced Fixes examples are not will_close targets and qualified refs stay non-local" {
  body=$(printf '%s\n' 'Why' '' '```text' 'Fixes #99' '```' '' 'Fixes #26' 'Fixes owner/other#8')
  write_pr "$body"
  write_issue $'## Acceptance\n- [x] **A1** done\n'
  write_binder $'## Acceptance\n- [x] **A1** done\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE" --json
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d.get("closing_ids")==[26], d; assert d.get("unsupported_closing_refs")==["owner/other#8"], d; assert d.get("ok") is True' "$output"
}

# ============================================================
# box syntax, deferral word boundary,
# fence-aware Refs, binder precedence
# ============================================================

@test "HARD: open box in '+ [ ]' bullet syntax is seen" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n+ [ ] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
}

@test "HARD: open box in ordered '1. [ ]' syntax is seen" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n1. [ ] **A1** first\n2. [ ] **A2** second\n'
  write_binder $'- [x] **A1** first\n- [x] **A2** second\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
}

@test "HARD: open box with double space after bullet is seen" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n-  [ ] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
}

@test "HARD: 'follow-up' mid-description does not defer a real criterion" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [ ] **A1** add follow-up email reminders\n'
  write_binder $'- [x] **A1** add follow-up email reminders\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
}

@test "ok: annotation-position deferral keywords still defer" {
  write_pr $'## Why\n\nShip demo body with enough text here.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n- [ ] **A2** deferred: follow-up ticket refs #99\n'
  write_binder $'- [x] **A1** first\n- [ ] **A2** deferred: follow-up ticket refs #99\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
}

@test "'undeferred' never matches the deferral keyword" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [ ] **A1** undeferred work item\n'
  write_binder $'- [x] **A1** undeferred work item\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "HARD gaps"
}

@test "fenced 'Refs #N' example does not load the issue" {
  write_pr $'## Why\n\nShip demo.\n\nFixes #26\n\n```\nRefs #4242\n```\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "Refs: (none)"
  [ -z "$(printf '%s\n' "$output" | grep -F "4242")" ]
}

@test "inline 'Refs #N' code-span example does not load the issue" {
  # An inline `Refs #4242` mention in prose must be stripped just like a
  # fenced example — the refs scan shares the closing extractor's code-span
  # handling, so this must not load issue #4242 as a real reference.
  write_pr $'## Why\n\nShip demo. Documents the closing syntax with `Refs #4242` inline.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "Refs: (none)"
  [ -z "$(printf '%s\n' "$output" | grep -F "4242")" ]
}

@test "live binder shadows archived copy of the same ticket" {
  write_pr $'## Why\n\nShip demo body with enough text.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  # stale archived copy still has the box open — must not shadow the live one
  mkdir -p "$LATTICE/tickets/archive/tkt-26-demo"
  cat >"$LATTICE/tickets/archive/tkt-26-demo/README.md" <<ARCH
# tkt-26-demo

| Field | Value |
| --- | --- |
| status | closed |

## Acceptance (this slice)

- [ ] **A1** first
ARCH
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
}

@test "two live binder dirs for one id warn about ambiguity" {
  write_pr $'## Why\n\nShip demo body with enough text.\n\nFixes #26\n'
  write_issue $'### Acceptance\n- [x] **A1** first\n'
  write_binder $'- [x] **A1** first\n'
  mkdir -p "$LATTICE/tickets/tkt-26-zother"
  cp "$LATTICE/tickets/tkt-26-demo/README.md" "$LATTICE/tickets/tkt-26-zother/README.md"
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ambiguous binder dirs for tkt-26"
}

@test "WARN: Fixes issue closed as NOT_PLANNED while PR delivers it (tkt-294)" {
  # Override the PR JSON with a GitHub-style URL so repo_id extraction works.
  python3 - <<'PY' >"$GH_PR_JSON"
import json, sys
json.dump({
  "number": 99, "title": "feat: demo", "body": "## Why\n\nShip demo.\n\nFixes #26\n",
  "state": "OPEN", "headRefName": "feat/tkt-99-demo", "baseRefName": "dev",
  "url": "https://github.com/acme/r/pull/99", "isDraft": False, "mergeable": "MERGEABLE",
}, sys.stdout)
PY
  # Issue is CLOSED with all Acceptance checked
  python3 - <<'PY' >"$GH_ISSUE_JSON"
import json, sys
json.dump({
  "number": 26, "title": "demo ticket",
  "body": "### Acceptance\n- [x] **A1** first\n",
  "state": "CLOSED", "labels": [],
}, sys.stdout)
PY
  write_binder $'- [x] **A1** first\n'
  # Override the stub to also handle gh api repos/.../issues/... returning state_reason
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${GH_CALL_LOG:-/dev/null}"
if [[ "$1" == "pr" && "$2" == "view" ]]; then cat "${GH_PR_JSON:?}"; exit 0; fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then cat "${GH_ISSUE_JSON:?}"; exit 0; fi
if [[ "$1" == "api" && "$2" == repos/*issues/* ]]; then printf 'not_planned'; exit 0; fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  run bash "$ALIGN" --pr 99 --home "$LATTICE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "NOT_PLANNED"
  printf '%s\n' "$output" | grep -qF "reconcile close-reason"
}
