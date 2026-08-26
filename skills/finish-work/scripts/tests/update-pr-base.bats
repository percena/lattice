#!/usr/bin/env bats
# Tests for update-pr-base.sh --rebase: worktree-aware rebase,
# local-ahead refusal, JSON summary on abort. Stubbed gh, real git + bare origin.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export UPDATE="$REPO_ROOT/skills/finish-work/scripts/update-pr-base.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upd-pr-base.XXXXXX")"
  ORIGIN="$TEST_DIR/origin.git"
  MAIN="$TEST_DIR/repo"
  git init -q --bare "$ORIGIN"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base-1
  git -C "$MAIN" remote add origin "$ORIGIN"
  git -C "$MAIN" push -q -u origin main
  # head branch from base-1, then base advances -> PR is BEHIND
  git -C "$MAIN" branch tkt-6-feature
  git -C "$MAIN" push -q origin tkt-6-feature
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base-2
  git -C "$MAIN" push -q origin main
  # standard layout: head branch checked out in its own worktree
  WT="$TEST_DIR/wt"
  git -C "$MAIN" worktree add -q "$WT" tkt-6-feature

  HEAD_OID=$(git -C "$MAIN" rev-parse origin/tkt-6-feature)
  BASE_OID=$(git -C "$MAIN" rev-parse origin/main)
  PR_VIEW_JSON="$TEST_DIR/pr-view.json"
  cat >"$PR_VIEW_JSON" <<EOF
{"id":"PR_node1","number":6,"url":"https://example.test/pr/6","state":"OPEN",
 "title":"feat: demo","headRefName":"tkt-6-feature","headRefOid":"$HEAD_OID",
 "headRepository":{"nameWithOwner":"acme/r"},"isCrossRepository":false,
 "baseRefName":"main","baseRefOid":"$BASE_OID",
 "mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","isDraft":false}
EOF
  PR_VIEW2_JSON="$TEST_DIR/pr-view2.json"
  cat >"$PR_VIEW2_JSON" <<EOF
{"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"$HEAD_OID"}
EOF

  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"--json id,number"*) cat "$PR_VIEW_JSON" ;;
  *"--json mergeable,mergeStateStatus,headRefOid"*) cat "$PR_VIEW2_JSON" ;;
  *"--json nameWithOwner,defaultBranchRef"*) echo '{"nameWithOwner":"acme/r","defaultBranchRef":{"name":"main"}}' ;;
  *"--json nameWithOwner"*) echo '{"nameWithOwner":"acme/r"}' ;;
  "pr diff"*)
    # Stateful: first call serves the pre-update diff, later calls the
    # post-update diff (used by the update_branch diff_changed probe).
    if [[ -f "$TEST_DIR/prdiff.called" ]]; then
      cat "$TEST_DIR/postdiff"
    else
      : >"$TEST_DIR/prdiff.called"
      cat "$TEST_DIR/prediff"
    fi
    ;;
  "api graphql"*) echo '{"data":{"updatePullRequestBranch":{"pullRequest":{"headRefOid":"x"}}}}' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  export PR_VIEW_JSON PR_VIEW2_JSON TEST_DIR
  cd "$MAIN"
}

# Regenerate the PR view fixtures for a given head branch from current origin
# tips (base = main, mergeStateStatus BEHIND, post-update view CLEAN).
make_pr_view() {
  local head_branch="$1" head_oid base_oid
  git -C "$MAIN" fetch -q origin
  head_oid=$(git -C "$MAIN" rev-parse "origin/$head_branch")
  base_oid=$(git -C "$MAIN" rev-parse origin/main)
  cat >"$PR_VIEW_JSON" <<EOF
{"id":"PR_node1","number":6,"url":"https://example.test/pr/6","state":"OPEN",
 "title":"feat: demo","headRefName":"$head_branch","headRefOid":"$head_oid",
 "headRepository":{"nameWithOwner":"acme/r"},"isCrossRepository":false,
 "baseRefName":"main","baseRefOid":"$base_oid",
 "mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","isDraft":false}
EOF
  cat >"$PR_VIEW2_JSON" <<EOF
{"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"$head_oid"}
EOF
}

tcommit() {
  # tcommit <dir> <message> [git-add args...]
  local dir="$1" msg="$2"
  shift 2
  if [[ $# -gt 0 ]]; then git -C "$dir" add "$@"; fi
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m "$msg"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

last_json() {
  printf '%s\n' "$1" | grep '^{' | tail -1
}

@test "--rebase runs inside the head worktree; main checkout is untouched" {
  run bash "$UPDATE" --pr 6 --rebase
  [ "$status" -eq 0 ]
  last_json "$output" | jq -e '.ok == true and .action == "rebase"'
  # origin head now contains the advanced base (rebased + pushed)
  git -C "$MAIN" fetch -q origin
  git -C "$MAIN" merge-base --is-ancestor origin/main origin/tkt-6-feature
  # the main checkout never switched branches
  [ "$(git -C "$MAIN" branch --show-current)" = "main" ]
  [ "$(git -C "$WT" branch --show-current)" = "tkt-6-feature" ]
}

@test "local branch ahead of origin is refused with JSON summary" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m unpushed
  run bash "$UPDATE" --pr 6 --rebase
  [ "$status" -eq 1 ]
  last_json "$output" | jq -e '.ok == false and .reason == "local_ahead"'
  # remote head untouched
  [ "$(git -C "$MAIN" rev-parse origin/tkt-6-feature)" = "$HEAD_OID" ]
}

@test "--allow-local-ahead publishes the unpushed commit deliberately" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m unpushed
  run bash "$UPDATE" --pr 6 --rebase --allow-local-ahead
  [ "$status" -eq 0 ]
  last_json "$output" | jq -e '.ok == true and .action == "rebase"'
  git -C "$MAIN" fetch -q origin
  git -C "$MAIN" log --format=%s origin/tkt-6-feature | grep -qx unpushed
}

@test "head OID drift between view and fetch aborts with JSON summary" {
  # origin advances after the PR view snapshot
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m sneak
  git -C "$WT" push -q origin tkt-6-feature
  run bash "$UPDATE" --pr 6 --rebase
  [ "$status" -eq 1 ]
  last_json "$output" | jq -e '.ok == false and .reason == "head_oid_changed"'
}

@test "noop (already up to date) reports diff_changed false and conflict false" {
  sed 's/"mergeStateStatus":"BEHIND"/"mergeStateStatus":"CLEAN"/' "$PR_VIEW_JSON" \
    >"$PR_VIEW_JSON.tmp" && mv "$PR_VIEW_JSON.tmp" "$PR_VIEW_JSON"
  run bash "$UPDATE" --pr 6
  [ "$status" -eq 0 ]
  last_json "$output" | jq -e '.ok == true and .action == "noop" and .diff_changed == false and .conflict == false'
}

@test "rebase that shifts the diff content reports diff_changed true" {
  # ancestor file on main, shared by base and head
  printf 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n' >"$MAIN/file.txt"
  tcommit "$MAIN" ancestor-file file.txt
  git -C "$MAIN" push -q origin main
  git -C "$MAIN" branch tkt-7-feature
  git -C "$MAIN" push -q origin tkt-7-feature
  WT2="$TEST_DIR/wt2"
  git -C "$MAIN" worktree add -q "$WT2" tkt-7-feature
  # head edits the last line
  sed 's/^l10$/l10-feature/' "$WT2/file.txt" >"$WT2/file.txt.tmp" && mv "$WT2/file.txt.tmp" "$WT2/file.txt"
  tcommit "$WT2" head-edit file.txt
  git -C "$WT2" push -q origin tkt-7-feature
  # base inserts lines at the top -> hunk offsets shift after rebase
  printf 'top1\ntop2\ntop3\n' | cat - "$MAIN/file.txt" >"$MAIN/file.txt.tmp" && mv "$MAIN/file.txt.tmp" "$MAIN/file.txt"
  tcommit "$MAIN" base-top-insert file.txt
  git -C "$MAIN" push -q origin main
  make_pr_view tkt-7-feature
  run bash "$UPDATE" --pr 6 --rebase
  [ "$status" -eq 0 ]
  last_json "$output" | jq -e '.ok == true and .action == "rebase" and .diff_changed == true and .conflict == false'
}

@test "clean rebase with untouched files reports diff_changed false" {
  git -C "$MAIN" branch tkt-8-feature
  git -C "$MAIN" push -q origin tkt-8-feature
  WT2="$TEST_DIR/wt8"
  git -C "$MAIN" worktree add -q "$WT2" tkt-8-feature
  # head adds its own file; base advances on an unrelated file
  echo feature >"$WT2/feat.txt"
  tcommit "$WT2" head-add feat.txt
  git -C "$WT2" push -q origin tkt-8-feature
  echo base >"$MAIN/base.txt"
  tcommit "$MAIN" base-add base.txt
  git -C "$MAIN" push -q origin main
  make_pr_view tkt-8-feature
  run bash "$UPDATE" --pr 6 --rebase
  [ "$status" -eq 0 ]
  last_json "$output" | jq -e '.ok == true and .action == "rebase" and .diff_changed == false and .conflict == false'
}

@test "conflicting rebase aborts with conflict true in JSON" {
  echo hello >"$MAIN/conflict.txt"
  tcommit "$MAIN" ancestor conflict.txt
  git -C "$MAIN" push -q origin main
  git -C "$MAIN" branch tkt-9-feature
  git -C "$MAIN" push -q origin tkt-9-feature
  WT2="$TEST_DIR/wt9"
  git -C "$MAIN" worktree add -q "$WT2" tkt-9-feature
  echo head-side >"$WT2/conflict.txt"
  tcommit "$WT2" head-edit conflict.txt
  git -C "$WT2" push -q origin tkt-9-feature
  echo base-side >"$MAIN/conflict.txt"
  tcommit "$MAIN" base-edit conflict.txt
  git -C "$MAIN" push -q origin main
  make_pr_view tkt-9-feature
  run bash "$UPDATE" --pr 6 --rebase
  [ "$status" -eq 1 ]
  last_json "$output" | jq -e '.ok == false and .reason == "rebase_failed" and .conflict == true'
  # worktree left clean (rebase aborted)
  [ -z "$(git -C "$WT2" status --porcelain)" ]
}

@test "update_branch with changed PR diff reports diff_changed true" {
  printf 'diff --git a/x b/x\n-old\n+new\n' >"$TEST_DIR/prediff"
  printf 'diff --git a/x b/x\n-old2\n+new2\n' >"$TEST_DIR/postdiff"
  run bash "$UPDATE" --pr 6
  [ "$status" -eq 0 ]
  last_json "$output" | jq -e '.ok == true and .action == "update_branch" and .diff_changed == true and .conflict == false'
}

@test "update_branch with identical PR diff reports diff_changed false" {
  printf 'diff --git a/x b/x\n-old\n+new\n' >"$TEST_DIR/prediff"
  printf 'diff --git a/x b/x\n-old\n+new\n' >"$TEST_DIR/postdiff"
  run bash "$UPDATE" --pr 6
  [ "$status" -eq 0 ]
  last_json "$output" | jq -e '.ok == true and .action == "update_branch" and .diff_changed == false and .conflict == false'
}
