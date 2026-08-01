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
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  export PR_VIEW_JSON PR_VIEW2_JSON
  cd "$MAIN"
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
