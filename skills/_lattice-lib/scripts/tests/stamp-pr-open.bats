#!/usr/bin/env bats
# Tests for stamp-pr-open.sh: post-`gh pr create` binder + issue acceptance sync.
# All GitHub traffic goes through a fake `gh` on PATH (finish-ledger.bats style).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export SPO="$REPO_ROOT/skills/_lattice-lib/scripts/stamp-pr-open.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spo.XXXXXX")"
  # Real layout: binder under <repo>/.lattice/tickets/<bind>/README.md; the
  # script refuses paths outside a repo's .lattice/ tree.
  REPO="$TEST_DIR/repo"
  BINDER_DIR="$REPO/.lattice/tickets/tkt-7-demo"
  mkdir -p "$BINDER_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  git -C "$REPO" remote add origin https://github.com/acme/repo.git
  BINDER="$BINDER_DIR/README.md"
  GH_LOG="$TEST_DIR/gh.log"
  ISSUE_BODY="$TEST_DIR/issue-body.md"
  write_fake_gh
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Fake gh: logs every invocation; answers repo/pr/issue queries from test
# fixtures; `issue edit --body-file` captures the new body it was handed.
write_fake_gh() {
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1 $2" in
  "repo view") printf '%s\n' 'https://github.com/acme/repo' ;;
  "pr view")   printf '%s\n' '{"url":"https://github.com/acme/repo/pull/12","state":"OPEN"}' ;;
  "issue view")
    if [[ "$*" == *comments* ]]; then
      # comments fixture: empty unless the test wrote one
      if [[ -f "$GH_COMMENTS" ]]; then cat "$GH_COMMENTS"; else printf '%s\n' '{"comments":[]}'; fi
    else
      python3 -c 'import json,sys; print(json.dumps({"body": open(sys.argv[1]).read()}))' "$ISSUE_BODY"
    fi
    ;;
  "issue edit")
    # capture --body-file payload
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--body-file" ]]; then cp "$2" "$GH_EDITED_BODY"; shift 2; else shift; fi
    done
    ;;
  "issue comment")
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--body-file" ]]; then cp "$2" "$GH_POSTED_COMMENT"; shift 2; else shift; fi
    done
    ;;
esac
exit 0
EOF
  chmod +x "$TEST_DIR/bin/gh"
}

run_spo() {
  run env PATH="$TEST_DIR/bin:$PATH" GH_LOG="$GH_LOG" ISSUE_BODY="$ISSUE_BODY" \
    GH_COMMENTS="$TEST_DIR/comments.json" GH_EDITED_BODY="$TEST_DIR/edited-body.md" \
    GH_POSTED_COMMENT="$TEST_DIR/posted-comment.md" \
    bash "$SPO" "$@"
}

write_fresh_binder() {
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| Field | Value |
| --- | --- |
| github | https://github.com/acme/repo/issues/7 |
| status | in-progress |
| adopted | false |
| prs | (none) |

## Acceptance (this slice)

- [x] **A1** first thing done
- [ ] **A2** second thing not done

## Finish

- (none yet)
MD
}

write_issue_body() {
  cat >"$ISSUE_BODY" <<'MD'
### Why

Because.

### Acceptance

- [ ] **A1** first thing done
- [ ] **A2** second thing not done

### Lineage

- Binder: `.lattice/tickets/tkt-7-demo/`
MD
}

@test "canonical stamp: prs row, status pr-open, issue body A1 checked" {
  write_fresh_binder
  write_issue_body
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"binder stamped"* ]]
  grep -q '| prs | pr-12 — https://github.com/acme/repo/pull/12 |' "$BINDER"
  grep -q '| status | pr-open |' "$BINDER"
  # issue number parsed from the binder github row; body edited via --body-file
  grep -Fq -- 'issue edit 7' "$GH_LOG"
  grep -q -- '- \[x\] \*\*A1\*\* first thing done' "$TEST_DIR/edited-body.md"
  [[ "$output" == *"checked 1 acceptance box(es) on issue #7"* ]]
}

@test "A*-id match: A1 checked mirrors only A1; A2 stays unchecked" {
  write_fresh_binder
  write_issue_body
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -q -- '- \[x\] \*\*A1\*\* first thing done' "$TEST_DIR/edited-body.md"
  grep -q -- '- \[ \] \*\*A2\*\* second thing not done' "$TEST_DIR/edited-body.md"
  # sections outside Acceptance untouched
  grep -q 'Because.' "$TEST_DIR/edited-body.md"
}

@test "idempotent second run: no second binder change, no second issue edit" {
  write_fresh_binder
  write_issue_body
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  # feed the edited body back as the live issue body (as GitHub would serve it)
  cp "$TEST_DIR/edited-body.md" "$ISSUE_BODY"
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"binder no change (idempotent)"* ]]
  [[ "$output" == *"already in sync (idempotent)"* ]]
  [ "$(grep -c 'pr-12' "$BINDER")" -eq 1 ]
  [ "$(grep -c -- 'issue edit 7' "$GH_LOG")" -eq 1 ]
}

@test "adopted binder: one comment, body never edited" {
  write_fresh_binder
  write_issue_body
  sed -i.bak 's/| adopted | false |/| adopted | true |/' "$BINDER"
  rm -f "$BINDER.bak"
  cp "$ISSUE_BODY" "$TEST_DIR/body-before.md"
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"posted acceptance comment"* ]]
  grep -Fq -- 'issue comment 7' "$GH_LOG"
  ! grep -q -- 'issue edit' "$GH_LOG"
  grep -q -- '- \[x\] \*\*A1\*\* first thing done' "$TEST_DIR/posted-comment.md"
  grep -Fq 'lattice:stamp-pr-open pr-12' "$TEST_DIR/posted-comment.md"
  # a re-run that sees its own comment posts nothing
  python3 -c 'import json,sys; print(json.dumps({"comments":[{"body": open(sys.argv[1]).read()}]}))' \
    "$TEST_DIR/posted-comment.md" >"$TEST_DIR/comments.json"
  : >"$GH_LOG"
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already carries the pr-12 comment (idempotent)"* ]]
  ! grep -q -- 'issue comment' "$GH_LOG"
}

@test "id-less binder items mirror by ordinal position" {
  write_fresh_binder
  # strip ids from binder AND issue (hand-styled acceptance lists)
  sed -i.bak 's/\*\*A1\*\* //; s/\*\*A2\*\* //' "$BINDER"
  rm -f "$BINDER.bak"
  write_issue_body
  sed -i.bak 's/\*\*A1\*\* first thing done/marker whitelist lands/; s/\*\*A2\*\* second thing not done/helper documented/' "$ISSUE_BODY"
  rm -f "$ISSUE_BODY.bak"
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -q -- '- \[x\] marker whitelist lands' "$TEST_DIR/edited-body.md"
  grep -q -- '- \[ \] helper documented' "$TEST_DIR/edited-body.md"
}

@test "dry-run mutates nothing: binder unchanged, no gh mutations" {
  write_fresh_binder
  write_issue_body
  cp "$BINDER" "$TEST_DIR/binder-before.md"
  run_spo --pr 12 --binder "$BINDER" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
  cmp -s "$BINDER" "$TEST_DIR/binder-before.md"
  ! grep -q -- 'issue edit' "$GH_LOG"
  ! grep -q -- 'issue comment' "$GH_LOG"
  [ ! -f "$TEST_DIR/edited-body.md" ]
}

@test "no binder file: skip with note, exit 0 (ticket-only flow)" {
  run_spo --pr 12 --binder "$BINDER_DIR/nonexistent.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
}

@test "refuses a non-numeric --pr and a non-OPEN PR" {
  write_fresh_binder
  write_issue_body
  run_spo --pr "https://github.com/attacker/repo/pull/1" --binder "$BINDER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pr must be a positive GitHub PR number"* ]]

  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") printf '%s\n' 'https://github.com/acme/repo' ;;
  "pr view")   printf '%s\n' '{"url":"https://github.com/acme/repo/pull/12","state":"MERGED"}' ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not OPEN"* ]]
  grep -q '| prs | (none) |' "$BINDER"
}

@test "refuses to stamp a PR from a different repository" {
  write_fresh_binder
  write_issue_body
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" ]]; then printf '%s\n' 'https://github.com/owner-b/repo-b'; exit 0; fi
printf '%s\n' '{"url":"https://github.com/owner-b/repo-b/pull/12","state":"OPEN"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run_spo --pr 12 --binder "$BINDER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"different repository"* ]]
  grep -q '| prs | (none) |' "$BINDER"
}

@test "--check-all checks every unchecked binder box, then mirrors all items" {
  write_fresh_binder
  write_issue_body
  run_spo --pr 12 --binder "$BINDER" --check-all
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 acceptance box(es) checked"* ]]
  # binder: A2 now checked too; canonical stamp still applied
  grep -q -- '- \[x\] \*\*A1\*\* first thing done' "$BINDER"
  grep -q -- '- \[x\] \*\*A2\*\* second thing not done' "$BINDER"
  grep -q '| prs | pr-12 — https://github.com/acme/repo/pull/12 |' "$BINDER"
  grep -q '| status | pr-open |' "$BINDER"
  # issue: BOTH boxes mirrored in one pass
  grep -q -- '- \[x\] \*\*A1\*\* first thing done' "$TEST_DIR/edited-body.md"
  grep -q -- '- \[x\] \*\*A2\*\* second thing not done' "$TEST_DIR/edited-body.md"
  [[ "$output" == *"checked 2 acceptance box(es) on issue #7"* ]]
}

@test "--check-all refuses when the Acceptance section carries a deferral note" {
  write_fresh_binder
  write_issue_body
  # a deliberately-open box with a deferral note (parked scope)
  sed -i.bak 's/- \[ \] \*\*A2\*\* second thing not done/- [ ] **A2** second thing not done — deferred to tkt-99/' "$BINDER"
  rm -f "$BINDER.bak"
  cp "$BINDER" "$TEST_DIR/binder-before.md"
  run_spo --pr 12 --binder "$BINDER" --check-all
  [ "$status" -eq 1 ]
  [[ "$output" == *"--check-all refused"* ]]
  [[ "$output" == *"deferred to tkt-99"* ]]
  # nothing mutated: binder byte-identical, no gh issue traffic
  cmp -s "$BINDER" "$TEST_DIR/binder-before.md"
  ! grep -q -- 'issue edit' "$GH_LOG"
  ! grep -q -- 'issue comment' "$GH_LOG"
}

@test "usage header states the ordering law (check boxes, then stamp)" {
  run_spo --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"check binder acceptance boxes, then stamp"* ]]
  [[ "$output" == *"mirrors only checked boxes"* ]]
  [[ "$output" == *"--check-all"* ]]
}
