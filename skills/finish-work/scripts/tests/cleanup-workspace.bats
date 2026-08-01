#!/usr/bin/env bats
# Tests for cleanup-workspace.sh (worktree/branch removal, dry-run, safety rails)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export CLEANUP="$REPO_ROOT/skills/finish-work/scripts/cleanup-workspace.sh"
  export ENSURE="$REPO_ROOT/skills/_lattice-lib/scripts/ensure-workspace.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cleanup-ws.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cd "$MAIN"
  bash "$ENSURE" --mode worktree --bind tkt --id 5 --slug victim >/dev/null
  WT="$TEST_DIR/repo.worktrees/tkt-5-victim"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "dry-run reports actions but removes nothing and stays offline" {
  # remote delete is default — no --delete-remote required
  run bash "$CLEANUP" --branch tkt-5-victim --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"dry_run": true'* ]]
  [[ "$output" == *"DRY:"* ]]
  [ -d "$WT" ]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
  # offline contract: the intended remote delete is logged, not probed
  [[ "$output" == *"remote stays unprobed"* ]]
  # must not claim the remote was deleted without ls-remote
  [[ "$output" == *'"deleted_remote_branch": false'* ]]
  # fully merged tip may claim local delete intent
  [[ "$output" == *'"deleted_local_branch": true'* ]]
}

@test "dry-run does not claim local delete success for an unmerged unique tip" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature tip"
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"
  run bash "$CLEANUP" --branch tkt-5-victim --keep-remote --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *'"dry_run": true'* ]]
  [[ "$output" == *'"deleted_local_branch": false'* ]]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  [[ "$output" == *'"ok": false'* ]]
  [ -d "$WT" ]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "dirty non-force dry-run predicts the real refusal" {
  echo x >"$WT/dirty.txt"
  run bash "$CLEANUP" --branch tkt-5-victim --keep-remote --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *'"ok": false'* ]]
  [[ "$output" == *'"was_dirty": true'* ]]
  [[ "$output" == *'"removed_worktree": false'* ]]
  [[ "$output" == *'"deleted_local_branch": false'* ]]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  [ -d "$WT" ]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "dry-run --delete-remote is a no-op alias for the default" {
  run bash "$CLEANUP" --branch tkt-5-victim --dry-run --delete-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote stays unprobed"* ]]
  [[ "$output" == *'"deleted_remote_branch": false'* ]]
}

@test "dry-run --keep-remote skips remote delete intent" {
  run bash "$CLEANUP" --branch tkt-5-victim --dry-run --keep-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *'"dry_run": true'* ]]
  [[ "$output" != *"if remote branch exists"* ]]
  [[ "$output" != *"git push origin --delete"* ]]
  [ -d "$WT" ]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "real run removes worktree and merged branch" {
  run bash "$CLEANUP" --branch tkt-5-victim --keep-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *'"removed_worktree": true'* ]]
  [ ! -d "$WT" ]
  ! git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "refuses dirty worktree without --force" {
  echo x > "$WT/dirty.txt"
  run bash "$CLEANUP" --branch tkt-5-victim
  [ "$status" -eq 1 ]
  [[ "$output" == *"dirty"* ]]
  [ -d "$WT" ]
}

@test "--force removes dirty worktree" {
  echo x > "$WT/dirty.txt"
  run bash "$CLEANUP" --branch tkt-5-victim --force
  [ "$status" -eq 0 ]
  [ ! -d "$WT" ]
}

@test "--keep-branch removes worktree but keeps the branch" {
  run bash "$CLEANUP" --branch tkt-5-victim --keep-branch
  [ "$status" -eq 0 ]
  [ ! -d "$WT" ]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "--keep-worktree does not delete the branch that remains checked out" {
  tip=$(git -C "$WT" rev-parse HEAD)
  run bash "$CLEANUP" --branch tkt-5-victim --keep-worktree --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"branch that remains checked out"* ]]
  [[ "$output" == *'"deleted_local_branch": false'* ]]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  [ -d "$WT" ]
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
  [ "$(git -C "$WT" rev-parse HEAD)" = "$tip" ]
}

@test "keeping the worktree branch and remote is a successful no-op" {
  tip=$(git -C "$WT" rev-parse HEAD)
  run bash "$CLEANUP" --branch tkt-5-victim --keep-worktree --keep-branch --keep-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]]
  [[ "$output" == *'"unsafe_delete_blocked": false'* ]]
  [ -d "$WT" ]
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
  [ "$(git -C "$WT" rev-parse HEAD)" = "$tip" ]
}

@test "local deletion is blocked when another worktree still checks out the branch" {
  SECOND_WT="$TEST_DIR/second-victim"
  git -C "$MAIN" worktree add -q --force "$SECOND_WT" tkt-5-victim

  run bash "$CLEANUP" --branch tkt-5-victim --worktree-path "$WT" --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"branch that remains checked out"* ]]
  [[ "$output" == *'"removed_worktree": true'* ]]
  [[ "$output" == *'"deleted_local_branch": false'* ]]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  [ ! -d "$WT" ]
  [ -d "$SECOND_WT" ]
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "refuses to remove the main checkout" {
  run bash "$CLEANUP" --branch main --worktree-path "$MAIN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing"* ]]
}

@test "worktree path containing spaces is found and removed" {
  export WORKTREE_ROOT="$TEST_DIR/pool with spaces"
  bash "$ENSURE" --mode worktree --bind tkt --id 6 --slug spacey >/dev/null
  unset WORKTREE_ROOT
  SPACEY="$TEST_DIR/pool with spaces/tkt-6-spacey"
  [ -d "$SPACEY" ]
  run bash "$CLEANUP" --branch tkt-6-spacey
  [ "$status" -eq 0 ]
  [[ "$output" == *'"removed_worktree": true'* ]]
  [ ! -d "$SPACEY" ]
  ! git show-ref --verify --quiet refs/heads/tkt-6-spacey
}

@test "unmerged unique branch is preserved without force or merged PR proof" {
  # Simulate squash leftover without checking out the branch in MAIN (worktree
  # already holds tkt-5-victim). Commit on the feature tip via the worktree.
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature tip"
  # main advances separately so tip is not an ancestor → -d refuses
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"
  run bash "$CLEANUP" --branch tkt-5-victim --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  [[ "$output" == *'"deleted_local_branch": false'* ]]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "verified merged PR allows squash residual deletion for matching head oid" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature tip"
  tip=$(git -C "$WT" rev-parse HEAD)
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"state":"MERGED","headRefName":"tkt-5-victim","isCrossRepository":false,"headRefOid":"$tip"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run env PATH="$TEST_DIR/bin:$PATH" bash "$CLEANUP" --branch tkt-5-victim --pr 42 --keep-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *'"merged_proof": true'* ]]
  [[ "$output" == *'"deleted_local_branch": true'* ]]
  ! git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "merged PR name match without tip oid match preserves divergent local tip" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "merged tip"
  merged_oid=$(git -C "$WT" rev-parse HEAD)
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "new work after merge"
  new_oid=$(git -C "$WT" rev-parse HEAD)
  [ "$merged_oid" != "$new_oid" ]
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"state":"MERGED","headRefName":"tkt-5-victim","isCrossRepository":false,"headRefOid":"$merged_oid"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run env PATH="$TEST_DIR/bin:$PATH" bash "$CLEANUP" --branch tkt-5-victim --pr 999 --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *'"merged_proof": false'* ]]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  [[ "$output" == *'"deleted_local_branch": false'* ]]
  [[ "$output" == *"local branch tip does not match PR #999 headRefOid"* ]]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
  [ "$(git rev-parse tkt-5-victim)" = "$new_oid" ]
}

@test "local old PR head does not authorize deletion of an advanced remote ref" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "merged tip"
  merged_oid=$(git -C "$WT" rev-parse HEAD)
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"

  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin tkt-5-victim
  git -C "$MAIN" worktree add -q -b remote-advance "$TEST_DIR/remote-advance" tkt-5-victim
  git -C "$TEST_DIR/remote-advance" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "remote reuse"
  remote_oid=$(git -C "$TEST_DIR/remote-advance" rev-parse HEAD)
  git -C "$TEST_DIR/remote-advance" push -q origin HEAD:refs/heads/tkt-5-victim

  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"state":"MERGED","headRefName":"tkt-5-victim","isCrossRepository":false,"headRefOid":"$merged_oid"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env PATH="$TEST_DIR/bin:$PATH" bash "$CLEANUP" --branch tkt-5-victim --pr 42
  [ "$status" -eq 1 ]
  [[ "$output" == *'"local_pr_proof": true'* ]]
  [[ "$output" == *'"remote_pr_proof": false'* ]]
  [[ "$output" == *'"deleted_local_branch": true'* ]]
  [[ "$output" == *'"deleted_remote_branch": false'* ]]
  [[ "$output" == *'"remote_residual": true'* ]]
  [[ "$output" == *'"ok": false'* ]]
  ! git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
  [ "$(git -C "$MAIN" ls-remote --heads origin tkt-5-victim | cut -f1)" = "$remote_oid" ]
}

@test "safe local deletion does not authorize a divergent remote ref" {
  local_oid=$(git -C "$MAIN" rev-parse tkt-5-victim)
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin tkt-5-victim
  git -C "$MAIN" worktree add -q -b remote-advance "$TEST_DIR/remote-advance" tkt-5-victim
  git -C "$TEST_DIR/remote-advance" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "remote-only work"
  remote_oid=$(git -C "$TEST_DIR/remote-advance" rev-parse HEAD)
  [ "$local_oid" != "$remote_oid" ]
  git -C "$TEST_DIR/remote-advance" push -q origin HEAD:refs/heads/tkt-5-victim

  run bash "$CLEANUP" --branch tkt-5-victim
  [ "$status" -eq 1 ]
  [[ "$output" == *'"deleted_local_branch": true'* ]]
  [[ "$output" == *'"local_deleted_oid": "'"$local_oid"'"'* ]]
  [[ "$output" == *'"deleted_remote_branch": false'* ]]
  [[ "$output" == *'"remote_residual": true'* ]]
  ! git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
  [ "$(git -C "$MAIN" ls-remote --heads origin tkt-5-victim | cut -f1)" = "$remote_oid" ]
}

@test "safe local deletion authorizes the identical remote ref with a lease" {
  tip=$(git -C "$MAIN" rev-parse tkt-5-victim)
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin tkt-5-victim

  run bash "$CLEANUP" --branch tkt-5-victim
  [ "$status" -eq 0 ]
  [[ "$output" == *'"deleted_local_branch": true'* ]]
  [[ "$output" == *'"local_deleted_oid": "'"$tip"'"'* ]]
  [[ "$output" == *'"remote_delete_expected_oid": "'"$tip"'"'* ]]
  [[ "$output" == *'"deleted_remote_branch": true'* ]]
  json_line=$(printf '%s\n' "$output" | tail -1)
  printf '%s' "$json_line" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin)["deleted_remote_branch"] is True else 1)'
  ! git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
  ! git -C "$MAIN" ls-remote --exit-code --heads origin tkt-5-victim >/dev/null
}

@test "runs from inside the target worktree: full cleanup including remote delete" {
  # The natural agent cwd is the worktree it just finished in. Removal
  # deletes that cwd; every later step must survive it (the remote delete
  # previously fataled on the dead cwd and left the remote branch behind).
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin tkt-5-victim

  cd "$WT"
  run bash "$CLEANUP" --branch tkt-5-victim
  cd "$MAIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"removed_worktree": true'* ]]
  [[ "$output" == *'"deleted_local_branch": true'* ]]
  [[ "$output" == *'"deleted_remote_branch": true'* ]]
  [ ! -d "$WT" ]
  ! git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
  ! git -C "$MAIN" ls-remote --exit-code --heads origin tkt-5-victim >/dev/null
}

@test "remote-only exact merged PR head is deleted with its OID lease" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature tip"
  tip=$(git -C "$WT" rev-parse HEAD)
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin tkt-5-victim
  git -C "$MAIN" worktree remove "$WT"
  git -C "$MAIN" branch -D tkt-5-victim >/dev/null

  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"state":"MERGED","headRefName":"tkt-5-victim","isCrossRepository":false,"headRefOid":"$tip"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env PATH="$TEST_DIR/bin:$PATH" bash "$CLEANUP" --branch tkt-5-victim --pr 42
  [ "$status" -eq 0 ]
  [[ "$output" == *'"remote_pr_proof": true'* ]]
  [[ "$output" == *'"deleted_remote_branch": true'* ]]
  json_line=$(printf '%s\n' "$output" | tail -1)
  printf '%s' "$json_line" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin)["deleted_remote_branch"] is True else 1)'
  expected_oid=$(printf '%s' "$json_line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["remote_delete_expected_oid"])')
  [ "$expected_oid" = "$tip" ]
  ! git -C "$MAIN" ls-remote --exit-code --heads origin tkt-5-victim >/dev/null
}

@test "remote lease preserves a ref advanced after proof" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature tip"
  tip=$(git -C "$WT" rev-parse HEAD)
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin tkt-5-victim

  git -C "$MAIN" worktree add -q -b race-source "$TEST_DIR/race-source" tkt-5-victim
  git -C "$TEST_DIR/race-source" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "racing tip"
  race_oid=$(git -C "$TEST_DIR/race-source" rev-parse HEAD)
  git -C "$TEST_DIR/race-source" push -q origin HEAD:refs/heads/race-source

  real_git=$(command -v git)
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"state":"MERGED","headRefName":"tkt-5-victim","isCrossRepository":false,"headRefOid":"$tip"}'
EOF
  cat >"$TEST_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" push "* ]] && [[ " $* " == *" --delete tkt-5-victim "* ]]; then
  "$REAL_GIT" --git-dir="$REMOTE" update-ref refs/heads/tkt-5-victim "$RACE_OID"
fi
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$TEST_DIR/bin/gh" "$TEST_DIR/bin/git"

  run env PATH="$TEST_DIR/bin:$PATH" REAL_GIT="$real_git" REMOTE="$REMOTE" RACE_OID="$race_oid" \
    bash "$CLEANUP" --branch tkt-5-victim --pr 42
  [ "$status" -eq 1 ]
  [[ "$output" == *'"deleted_remote_branch": false'* ]]
  json_line=$(printf '%s\n' "$output" | tail -1)
  after_oid=$(printf '%s' "$json_line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["remote_after_oid"])')
  [ "$after_oid" = "$race_oid" ]
  [[ "$output" == *'"remote_residual": true'* ]]
  [ "$(git -C "$MAIN" ls-remote --heads origin tkt-5-victim | cut -f1)" = "$race_oid" ]
}

@test "remote ref created after absent proof is preserved and reported" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin HEAD:refs/heads/seed
  race_oid=$(git -C "$MAIN" rev-parse HEAD)

  real_git=$(command -v git)
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" ls-remote --heads origin refs/heads/tkt-5-victim "* ]]; then
  count=0
  [[ -f "$COUNT_FILE" ]] && count=$(<"$COUNT_FILE")
  count=$((count + 1))
  printf '%s\n' "$count" >"$COUNT_FILE"
  if [[ $count -eq 2 ]]; then
    "$REAL_GIT" --git-dir="$REMOTE" update-ref refs/heads/tkt-5-victim "$RACE_OID"
  fi
fi
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$TEST_DIR/bin/git"

  run env PATH="$TEST_DIR/bin:$PATH" REAL_GIT="$real_git" REMOTE="$REMOTE" RACE_OID="$race_oid" \
    COUNT_FILE="$TEST_DIR/ls-remote-count" bash "$CLEANUP" --branch tkt-5-victim
  [ "$status" -eq 1 ]
  [[ "$output" == *'"deleted_local_branch": true'* ]]
  [[ "$output" == *'"deleted_remote_branch": false'* ]]
  [[ "$output" == *'"remote_residual": true'* ]]
  json_line=$(printf '%s\n' "$output" | tail -1)
  after_oid=$(printf '%s' "$json_line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["remote_after_oid"])')
  [ "$after_oid" = "$race_oid" ]
  [ "$(git -C "$MAIN" ls-remote --heads origin tkt-5-victim | cut -f1)" = "$race_oid" ]
}

@test "local compare-and-delete preserves a ref changed after PR proof" {
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature tip"
  tip=$(git -C "$WT" rev-parse HEAD)
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "main advance"
  git -C "$MAIN" worktree add -q -b local-race-source "$TEST_DIR/local-race-source" tkt-5-victim
  git -C "$TEST_DIR/local-race-source" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "new local work"
  race_oid=$(git -C "$TEST_DIR/local-race-source" rev-parse HEAD)

  real_git=$(command -v git)
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"state":"MERGED","headRefName":"tkt-5-victim","isCrossRepository":false,"headRefOid":"$tip"}'
EOF
  cat >"$TEST_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" update-ref -d refs/heads/tkt-5-victim "* ]]; then
  "$REAL_GIT" -C "$MAIN" update-ref refs/heads/tkt-5-victim "$RACE_OID"
fi
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$TEST_DIR/bin/gh" "$TEST_DIR/bin/git"

  run env PATH="$TEST_DIR/bin:$PATH" REAL_GIT="$real_git" MAIN="$MAIN" RACE_OID="$race_oid" \
    bash "$CLEANUP" --branch tkt-5-victim --pr 42 --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *'"deleted_local_branch": false'* ]]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  [[ "$output" == *"local compare-and-delete failed"* ]]
  [ "$(git -C "$MAIN" rev-parse tkt-5-victim)" = "$race_oid" ]
}

@test "merged PR proof rejects a different head branch" {
  tip=$(git -C "$WT" rev-parse HEAD)
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '{"state":"MERGED","headRefName":"tkt-99-other","isCrossRepository":false,"headRefOid":"$tip"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run env PATH="$TEST_DIR/bin:$PATH" bash "$CLEANUP" --branch tkt-5-victim --pr 42 --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a merged same-repository PR"* ]]
  [ -d "$WT" ]
  git show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "refuses force-delete of protected branch name main" {
  run bash "$CLEANUP" --branch main --force --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"protected"* || "$output" == *"refusing"* ]]
}

@test "refuses remote-only protected branch deletion even with --force" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin HEAD:dev

  ! git -C "$MAIN" show-ref --verify --quiet refs/heads/dev
  run bash "$CLEANUP" --branch dev --force --keep-worktree
  [ "$status" -eq 1 ]
  [[ "$output" == *"protected remote branch"* ]]
  [[ "$output" == *'"unsafe_delete_blocked": true'* ]]
  git -C "$MAIN" ls-remote --exit-code --heads origin dev >/dev/null
}

@test "refuses configured custom default branch deletion even with --force" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin HEAD:release
  mkdir -p "$MAIN/.lattice"
  printf '%s\n' 'base_branch: origin/release' >"$MAIN/.lattice/config.yaml"

  ! git -C "$MAIN" show-ref --verify --quiet refs/heads/release
  run bash "$CLEANUP" --branch release --force --keep-worktree
  [ "$status" -eq 1 ]
  [[ "$output" == *"protected remote branch"* ]]
  git -C "$MAIN" ls-remote --exit-code --heads origin release >/dev/null
}

@test "JSON includes remote_residual false on keep-remote success" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin tkt-5-victim
  remote_oid=$(git -C "$MAIN" ls-remote --heads origin tkt-5-victim | cut -f1)

  run bash "$CLEANUP" --branch tkt-5-victim --keep-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *'"remote_residual": false'* ]]
  [[ "$output" == *'"ok": true'* ]]
  [ "$(git -C "$MAIN" ls-remote --heads origin tkt-5-victim | cut -f1)" = "$remote_oid" ]
}

@test "explicit worktree path for a different branch is not removed even with --force" {
  # Target branch has its own worktree; pass an unrelated registered path.
  bash "$ENSURE" --mode worktree --bind tkt --id 9 --slug other >/dev/null
  OTHER_WT="$TEST_DIR/repo.worktrees/tkt-9-other"
  [ -d "$OTHER_WT" ]
  [ -d "$WT" ]

  run bash "$CLEANUP" --branch tkt-5-victim --worktree-path "$OTHER_WT" --force --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not check out branch"* ]] || [[ "$output" == *"worktree_path_branch_mismatch"* ]]
  [[ "$output" == *'"removed_worktree": false'* ]]
  [[ "$output" == *'"worktree_identity_blocked": true'* ]]
  [[ "$output" == *'"worktree_identity_reason": "worktree_path_branch_mismatch"'* ]]
  [[ "$output" == *'"ok": false'* ]]
  [ -d "$OTHER_WT" ]
  [ -d "$WT" ]
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-9-other
}

@test "unregistered explicit worktree path is refused even with --force" {
  FAKE="$TEST_DIR/not-a-worktree"
  mkdir -p "$FAKE"
  run bash "$CLEANUP" --branch tkt-5-victim --worktree-path "$FAKE" --force --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a registered worktree"* ]]
  [[ "$output" == *'"removed_worktree": false'* ]]
  [[ "$output" == *'"worktree_identity_reason": "worktree_path_unregistered"'* ]]
  [ -d "$FAKE" ]
  [ -d "$WT" ]
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "detached explicit worktree path is refused even with --force" {
  DETACHED_WT="$TEST_DIR/detached-victim"
  tip=$(git -C "$MAIN" rev-parse HEAD)
  git -C "$MAIN" worktree add -q --detach "$DETACHED_WT" "$tip"

  run bash "$CLEANUP" --branch tkt-5-victim --worktree-path "$DETACHED_WT" --force --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"detached"* ]]
  [[ "$output" == *'"removed_worktree": false'* ]]
  [[ "$output" == *'"worktree_identity_reason": "worktree_path_detached"'* ]]
  [ -d "$DETACHED_WT" ]
  [ -d "$WT" ]
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-5-victim
}

@test "matching explicit worktree path still removes the bound tree" {
  run bash "$CLEANUP" --branch tkt-5-victim --worktree-path "$WT" --keep-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *'"removed_worktree": true'* ]]
  [[ "$output" != *'"worktree_identity_blocked": true'* ]]
  [ ! -d "$WT" ]
  ! git show-ref --verify --quiet refs/heads/tkt-5-victim
}

# ============================================================
# submodule refusal, JSON contract on
# refusal/abort paths (stdout: JSON summary last line)
# ============================================================

# Last stdout line must be a JSON object with the given reason and ok:false.
assert_refusal_json() {
  local out="$1" reason="$2"
  local last
  last=$(printf '%s\n' "$out" | grep '^{' | tail -1)
  [ -n "$last" ]
  printf '%s' "$last" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is False, d
assert d['reason'] == '$reason', d
assert d['unsafe_delete_blocked'] is True, d
"
}

@test "submodule checkout is refused with JSON contract" {
  SUB_SRC="$TEST_DIR/subsrc"
  mkdir -p "$SUB_SRC"
  git -C "$SUB_SRC" init -q -b main
  git -C "$SUB_SRC" config user.email lattice-test@example.invalid
  git -C "$SUB_SRC" config user.name 'Lattice Test'
  git -C "$SUB_SRC" -c user.email=t@t -c user.name=t commit -q --allow-empty -m sub-init
  git -C "$MAIN" -c protocol.file.allow=always submodule add -q "$SUB_SRC" embedded
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q -m add-submodule
  cd "$MAIN/embedded"
  run bash "$CLEANUP" --branch main --keep-remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"git submodule"* ]]
  assert_refusal_json "$output" "submodule_checkout"
}

@test "dirty refusal emits the JSON contract line" {
  echo x > "$WT/dirty.txt"
  run bash "$CLEANUP" --branch tkt-5-victim --keep-remote
  [ "$status" -eq 1 ]
  assert_refusal_json "$output" "dirty_worktree"
}

@test "not-inside-work-tree abort emits the JSON contract line" {
  cd "$TEST_DIR"
  mkdir -p notrepo && cd notrepo
  GIT_CEILING_DIRECTORIES="$TEST_DIR" run bash "$CLEANUP" --branch whatever --keep-remote
  [ "$status" -eq 1 ]
  assert_refusal_json "$output" "not_inside_git_work_tree"
}

@test "--pr without gh on PATH emits the JSON contract line" {
  NOGH_BIN="$TEST_DIR/nogh-bin"
  mkdir -p "$NOGH_BIN"
  for tool in git python3 bash mktemp dirname basename awk grep sed cat mkdir rm mv cp touch tail head find pwd env tr; do
    p="$(command -v "$tool" 2>/dev/null)" && ln -sf "$p" "$NOGH_BIN/$tool" || true
  done
  run env PATH="$NOGH_BIN" bash "$CLEANUP" --branch tkt-5-victim --keep-remote --pr 12
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires gh"* ]]
  assert_refusal_json "$output" "gh_required_for_pr_verification"
}

@test "set -e abort still ends with the JSON contract line" {
  # Force an internal failure after preflight: LATTICE_HOME as an unwritable
  # location is not it; instead break `git worktree list` via a shim that
  # fails only for that subcommand.
  SHIM="$TEST_DIR/failshim"
  mkdir -p "$SHIM"
  REAL_GIT="$(command -v git)"
  cat >"$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
  echo "simulated worktree list failure" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
  chmod +x "$SHIM/git"
  run env PATH="$SHIM:$PATH" bash "$CLEANUP" --branch tkt-5-victim --keep-remote
  [ "$status" -ne 0 ]
  assert_refusal_json "$output" "internal_error"
}

@test "destructive-phase abort (after ACTION_LOG setup) still ends with JSON" {
  # The ACTION_LOG mktemp happens mid-script; a second `trap ... EXIT` there
  # used to REPLACE the JSON backstop, so failures in the destructive phase
  # (worktree remove and later) exited with empty stdout.
  SHIM="$TEST_DIR/failshim2"
  mkdir -p "$SHIM"
  REAL_GIT="$(command -v git)"
  cat >"$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "-C" && "\$3" == "worktree" && "\$4" == "remove" ]]; then
  echo "simulated worktree remove failure" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
  chmod +x "$SHIM/git"
  run env PATH="$SHIM:$PATH" bash "$CLEANUP" --branch tkt-5-victim --keep-remote
  [ "$status" -ne 0 ]
  assert_refusal_json "$output" "internal_error"
}

@test "sibling ref whose name tail-matches the branch is never mistaken for it" {
  # `ls-remote --heads origin tkt-5-victim` also matches refs/heads/a/tkt-5-victim,
  # and the sibling sorts FIRST — binding the delete lease to a foreign OID.
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q origin "refs/heads/tkt-5-victim:refs/heads/tkt-5-victim"
  # Decoy on a DIFFERENT commit so a wrong pick cannot accidentally agree.
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m decoy
  git -C "$MAIN" push -q origin "HEAD:refs/heads/a/tkt-5-victim"
  decoy_oid=$(git -C "$MAIN" rev-parse HEAD)
  victim_oid=$(git -C "$MAIN" rev-parse refs/heads/tkt-5-victim)
  [ "$decoy_oid" != "$victim_oid" ]

  run bash "$CLEANUP" --branch tkt-5-victim
  [ "$status" -eq 0 ]
  [[ "$output" == *'"deleted_remote_branch": true'* ]]
  [[ "$output" == *'"remote_residual": false'* ]]
  # the exact branch is gone; the tail-matching sibling is untouched
  run git -C "$MAIN" ls-remote --heads origin "refs/heads/tkt-5-victim"
  [ -z "$output" ]
  run git -C "$MAIN" ls-remote --heads origin "refs/heads/a/tkt-5-victim"
  [[ "$output" == *"$decoy_oid"* ]]
}

@test "--branch refuses an option-shaped or malformed name" {
  run bash "$CLEANUP" --branch "--upload-pack=./x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a valid git branch name"* ]]

  run bash "$CLEANUP" --branch "bad..name"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a valid git branch name"* ]]
}
