#!/usr/bin/env bats
# Tests for ensure-workspace.sh (bound defaults plus reasoned capability escapes)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export ENSURE="$REPO_ROOT/skills/_lattice-lib/scripts/ensure-workspace.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ensure-ws.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cd "$MAIN"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "branch mode with tkt bind creates and checks out bound branch" {
  run bash "$ENSURE" --mode branch --bind tkt --id 12 --slug demo-work
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"branch": "tkt-12-demo-work"'
  [ "$(git branch --show-current)" = "tkt-12-demo-work" ]
}

@test "branch mode under strict warns that L2/L3 write-block (F2)" {
  mkdir -p "$MAIN/.lattice"
  printf 'profile: strict\n' >"$MAIN/.lattice/config.yaml"
  git -C "$MAIN" add .lattice && git -C "$MAIN" commit -q -m cfg
  run bash "$ENSURE" --mode branch --bind tkt --id 13 --slug demo 2>&1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "L2/L3 write-block"
  printf '%s\n' "$output" | grep -qF -- "--mode worktree"
}

@test "branch mode under light does not emit the L2/L3 write-block warning" {
  mkdir -p "$MAIN/.lattice"
  printf 'profile: light\n' >"$MAIN/.lattice/config.yaml"
  git -C "$MAIN" add .lattice && git -C "$MAIN" commit -q -m cfg
  run bash "$ENSURE" --mode branch --bind tkt --id 14 --slug demo 2>&1
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -F "L2/L3 write-block")" ]
}

@test "branch mode refuses dirty tree" {
  echo x > dirty.txt
  run bash "$ENSURE" --mode branch --bind tkt --id 12 --slug demo
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "dirty"
}

@test "worktree mode refuses unbound branch names without an explicit reasoned escape" {
  run bash "$ENSURE" --mode worktree --branch improve/foo
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must bind a ticket or Spec" || printf '%s\n' "$output" | grep -qF "tkt-"
}

@test "branch mode also refuses unbound branch names without an explicit reasoned escape" {
  run bash "$ENSURE" --mode branch --branch improve/foo
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must bind a ticket or Spec" || printf '%s\n' "$output" | grep -qF "tkt-"
}

@test "unbound workspace escape requires a reason" {
  run bash "$ENSURE" --mode worktree --branch smoke-test --allow-unbound
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "requires --reason"
}

@test "reasoned unbound workspace escape succeeds and is visible in JSON" {
  run bash "$ENSURE" --mode worktree --branch improve/better-plan --allow-unbound --reason "PR and branch record owner, scope, and rollback"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"bound": false'
  printf '%s\n' "$output" | grep -qF '"escape_reason": "PR and branch record owner, scope, and rollback"'
  [ -d "$TEST_DIR/repo.worktrees/improve-better-plan" ]
}

@test "unbound escape cannot target a fully qualified custom base branch" {
  git -C "$MAIN" branch release
  run bash "$ENSURE" --mode branch --branch release --base refs/heads/release --allow-unbound --reason "direct release work"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "protected/team-base branch"
}

@test "worktree lands in sibling <repo>.worktrees pool by default" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug pool-check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "repo.worktrees/tkt-7-pool-check"
  [ -d "$TEST_DIR/repo.worktrees/tkt-7-pool-check" ]
  git -C "$TEST_DIR/repo.worktrees/tkt-7-pool-check" rev-parse --is-inside-work-tree
}

@test "WORKTREE_ROOT env overrides the pool location" {
  export WORKTREE_ROOT="$TEST_DIR/custom-pool"
  run bash "$ENSURE" --mode worktree --bind tkt --id 8 --slug override
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/custom-pool/tkt-8-override" ]
  unset WORKTREE_ROOT
}

@test "type prefix produces feat/tkt-N-slug and dashes in path" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 9 --slug typed --type feat
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"branch": "feat/tkt-9-typed"'
  [ -d "$TEST_DIR/repo.worktrees/feat-tkt-9-typed" ]
}

@test "slug is normalized (case, spaces, punctuation)" {
  run bash "$ENSURE" --mode branch --bind tkt --id 3 --slug "My Fancy_Slug!!"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"branch": "tkt-3-my-fancy-slug"'
}

@test "spc bind normalizes zero-padded id" {
  run bash "$ENSURE" --mode branch --bind spc --id 001 --slug model
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"branch": "spc-1-model"'
}

@test "spc bind rejects id 0" {
  run bash "$ENSURE" --mode branch --bind spc --id 0 --slug fake
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "real Spec primary issue" || printf '%s\n' "$output" | grep -qF "≥1"
}

@test "pre-formed spc-0 branch is rejected" {
  run bash "$ENSURE" --mode worktree --branch spc-0-fake
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "spc-0" || printf '%s\n' "$output" | grep -qF "spc-<n≥1>"
}

@test "idempotent: re-running on existing branch succeeds" {
  bash "$ENSURE" --mode branch --bind tkt --id 4 --slug twice >/dev/null
  run bash "$ENSURE" --mode branch --bind tkt --id 4 --slug twice
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = "tkt-4-twice" ]
}

@test "reused existing branch exposes workspace head distinct from advanced base" {
  git -C "$MAIN" branch tkt-29-reuse
  old=$(git -C "$MAIN" rev-parse tkt-29-reuse)
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m later-base
  new=$(git -C "$MAIN" rev-parse main)
  [ "$old" != "$new" ]

  run env LATTICE_SKIP_FETCH=1 bash "$ENSURE" --mode worktree --branch tkt-29-reuse --base main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"reused_existing_branch": true'
  printf '%s\n' "$output" | grep -qF "\"base_start_oid\": \"$new\""
  printf '%s\n' "$output" | grep -qF "\"workspace_head_oid\": \"$old\""
  [ "$(git -C "$TEST_DIR/repo.worktrees/tkt-29-reuse" rev-parse HEAD)" = "$old" ]
}

@test "new branch workspace head matches resolved base start" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 30 --slug fresh-head
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"reused_existing_branch": false'
  # bats $output mixes streams; grab the JSON object line.
  base_oid=$(printf '%s\n' "$output" | python3 -c 'import sys,json,re; t=sys.stdin.read(); m=re.search(r"\{.*\}", t, re.S); d=json.loads(m.group()); print(d["base_start_oid"])')
  head_oid=$(printf '%s\n' "$output" | python3 -c 'import sys,json,re; t=sys.stdin.read(); m=re.search(r"\{.*\}", t, re.S); d=json.loads(m.group()); print(d["workspace_head_oid"])')
  [ "$base_oid" = "$head_oid" ]
}

@test "tkt bind rejects id 0" {
  run bash "$ENSURE" --mode branch --bind tkt --id 0 --slug fake
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "real GitHub issue" || printf '%s\n' "$output" | grep -qF "≥1" || printf '%s\n' "$output" | grep -qF ">=1" || printf '%s\n' "$output" | grep -qF "got: 0"
}

@test "branch name tkt-0-* is rejected by bound pattern" {
  run bash "$ENSURE" --mode worktree --branch tkt-0-fake
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must bind" || printf '%s\n' "$output" | grep -qF "tkt-"
}

@test "pre-formed bound --branch without --bind is accepted" {
  run bash "$ENSURE" --mode worktree --branch tkt-15-preformed
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"branch": "tkt-15-preformed"'
  [ -d "$TEST_DIR/repo.worktrees/tkt-15-preformed" ]
}

@test "JSON includes cd_hint for worktree mode" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 20 --slug cd-hint
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"cd_hint":'
  printf '%s\n' "$output" | grep -qF "tkt-20-cd-hint"
}

@test "default base prefers explicit --base over origin HEAD" {
  run bash "$ENSURE" --mode branch --bind tkt --id 21 --slug base-flag --base main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"base": "main"'
}

@test "fully qualified explicit base ref controls the actual branch start" {
  git -C "$MAIN" branch release
  git -C "$MAIN" switch -q release
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m release-advance
  release_oid=$(git -C "$MAIN" rev-parse release)
  git -C "$MAIN" switch -q main

  run bash "$ENSURE" --mode worktree --bind tkt --id 25 --slug qualified-base --base refs/heads/release
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"base": "refs/heads/release"'
  printf '%s\n' "$output" | grep -qF '"base_start": "refs/heads/release"'
  printf '%s\n' "$output" | grep -qF "\"base_start_oid\": \"$release_oid\""
  [ "$(git -C "$TEST_DIR/repo.worktrees/tkt-25-qualified-base" rev-parse HEAD)" = "$release_oid" ]
}

@test "fully qualified remote ref controls the actual branch start" {
  git -C "$MAIN" branch release
  git -C "$MAIN" switch -q -c remote-release release
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m remote-release-advance
  remote_oid=$(git -C "$MAIN" rev-parse HEAD)
  git -C "$MAIN" update-ref refs/remotes/origin/release "$remote_oid"
  git -C "$MAIN" switch -q main
  git -C "$MAIN" branch -D remote-release >/dev/null

  run env LATTICE_SKIP_FETCH=1 bash "$ENSURE" --mode worktree --bind tkt --id 27 --slug qualified-remote --base refs/remotes/origin/release
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"base_start": "refs/remotes/origin/release"'
  printf '%s\n' "$output" | grep -qF "\"base_start_oid\": \"$remote_oid\""
  [ "$(git -C "$TEST_DIR/repo.worktrees/tkt-27-qualified-remote" rev-parse HEAD)" = "$remote_oid" ]
}

@test "missing explicit base fails instead of silently using current HEAD" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 26 --slug missing-base --base refs/heads/does-not-exist
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "resolved base is not available"
  [ ! -d "$TEST_DIR/repo.worktrees/tkt-26-missing-base" ]
}

# Shared fixture for the two base-precedence tests below: remotes main + dev,
# origin/HEAD deliberately stale (→ main), and a gh stub reporting dev as the
# GitHub default.
stale_origin_head_repo() {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q -u origin main
  git -C "$MAIN" switch -q -c dev
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m dev-advance
  git -C "$MAIN" push -q -u origin dev
  git -C "$MAIN" switch -q main
  git -C "$MAIN" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' dev
EOF
  chmod +x "$TEST_DIR/bin/gh"
}

@test "user on a long-lived branch wins over the GitHub default (tkt-9)" {
  # tkt-9: PR base = the long-lived branch the worktree forked from = the user's
  # branch when it is long-lived. Standing on main means main, even though
  # GitHub reports dev as the repo default — basing on dev would silently
  # retarget the PR away from the branch the operator is working from.
  stale_origin_head_repo

  run env PATH="$TEST_DIR/bin:$PATH" LATTICE_SKIP_FETCH=1 bash "$ENSURE" --mode worktree --bind tkt --id 24 --slug live-default
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"base": "main"'
  printf '%s\n' "$output" | grep -qF '"base_source": "integration-branch:user_branch"'
  [ "$(git -C "$TEST_DIR/repo.worktrees/tkt-24-live-default" rev-parse HEAD)" = "$(git -C "$MAIN" rev-parse main)" ]
}

@test "GitHub dev default beats stale origin HEAD when no integration branch resolves" {
  # Detached HEAD → no user_branch and no fork-point, so the integration-branch
  # pipeline abstains and the gh default must still beat the stale origin/HEAD.
  stale_origin_head_repo
  git -C "$MAIN" checkout -q --detach main

  run env PATH="$TEST_DIR/bin:$PATH" LATTICE_SKIP_FETCH=1 bash "$ENSURE" --mode worktree --bind tkt --id 24 --slug live-default
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"base": "dev"'
  printf '%s\n' "$output" | grep -qF '"base_source": "gh-default"'
  [ "$(git -C "$TEST_DIR/repo.worktrees/tkt-24-live-default" rev-parse HEAD)" = "$(git -C "$MAIN" rev-parse dev)" ]
}

@test "a config base_branch that is not a ref name is refused (option injection)" {
  # base_branch comes from a CHECKED-OUT .lattice/config.yaml, and `git fetch`
  # keeps parsing options after the positional <repository>, so a leading '-'
  # would be read as a flag (--upload-pack=./x runs a local program).
  mkdir -p "$MAIN/.lattice"
  printf 'base_branch: --upload-pack=./evil.sh\n' >"$MAIN/.lattice/config.yaml"
  printf '#!/bin/sh\ntouch %s/pwned\n' "$TEST_DIR" >"$MAIN/evil.sh"
  chmod +x "$MAIN/evil.sh"

  run bash "$ENSURE" --mode worktree --bind tkt --id 30 --slug injected
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must not start with '-'"
  [ ! -e "$TEST_DIR/pwned" ]
  [ ! -d "$TEST_DIR/repo.worktrees/tkt-30-injected" ]
}

@test "explicit --base with a malformed ref name is refused" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 31 --slug badbase --base "bad..name"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "not a valid git ref name"
}

@test "successful fetch makes a short base use the fresh remote tip instead of stale local branch" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q -u origin main
  git -C "$MAIN" switch -q -c dev
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m local-dev
  git -C "$MAIN" push -q -u origin dev
  local_oid=$(git -C "$MAIN" rev-parse dev)

  git -C "$MAIN" switch -q -c remote-dev-update
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m remote-dev-advance
  remote_oid=$(git -C "$MAIN" rev-parse HEAD)
  git -C "$MAIN" push -q origin HEAD:dev
  git -C "$MAIN" switch -q main
  git -C "$MAIN" branch -D remote-dev-update >/dev/null
  [ "$(git -C "$MAIN" rev-parse dev)" = "$local_oid" ]
  [ "$local_oid" != "$remote_oid" ]

  run bash "$ENSURE" --mode worktree --bind tkt --id 28 --slug fresh-short-base --base dev
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"fetched": true'
  printf '%s\n' "$output" | grep -qF '"base_start": "refs/remotes/origin/dev"'
  printf '%s\n' "$output" | grep -qF "\"base_start_oid\": \"$remote_oid\""
  [ "$(git -C "$TEST_DIR/repo.worktrees/tkt-28-fresh-short-base" rev-parse HEAD)" = "$remote_oid" ]
}

@test "LATTICE_SKIP_FETCH=0 still fetches (truthiness, not set-ness)" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q -u origin main
  run env LATTICE_SKIP_FETCH=0 bash "$ENSURE" --mode worktree --bind tkt --id 33 --slug fetch-falsy --base main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"fetched": true'
  [ -z "$(printf '%s\n' "$output" | grep -F "skip fetch")" ]
}

@test "LATTICE_SKIP_FETCH=false still fetches" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q -u origin main
  run env LATTICE_SKIP_FETCH=false bash "$ENSURE" --mode worktree --bind tkt --id 34 --slug fetch-false --base main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"fetched": true'
}

@test "LATTICE_SKIP_FETCH=true skips the fetch (case-insensitive truthy)" {
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q -u origin main
  run env LATTICE_SKIP_FETCH=TRUE bash "$ENSURE" --mode worktree --bind tkt --id 35 --slug fetch-skip --base main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "skip fetch"
  printf '%s\n' "$output" | grep -qF '"fetched": false'
}

@test "failed worktree add removes the branch created this run (no residue)" {
  touch "$TEST_DIR/blocker"
  run bash "$ENSURE" --mode worktree --bind tkt --id 36 --slug residue --path "$TEST_DIR/blocker"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "worktree add failed"
  printf '%s\n' "$output" | grep -qF "removed just-created branch 'tkt-36-residue'"
  if git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-36-residue; then false; fi
}

@test "failed worktree add never deletes a reused pre-existing branch" {
  git -C "$MAIN" branch tkt-37-keep
  touch "$TEST_DIR/blocker2"
  run bash "$ENSURE" --mode worktree --branch tkt-37-keep --path "$TEST_DIR/blocker2"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "worktree add failed"
  printf '%s\n' "$output" | grep -qF "left untouched"
  git -C "$MAIN" show-ref --verify --quiet refs/heads/tkt-37-keep
}

@test "worktree lattice_home points at worktree path when LATTICE_HOME unset" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 22 --slug home-path
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"lattice_home":'
  # Must be the sibling worktree's .lattice, not the main checkout's
  printf '%s\n' "$output" | grep -qF "repo.worktrees/tkt-22-home-path/.lattice"
}

@test "worktree honours explicit LATTICE_HOME env" {
  export LATTICE_HOME="$TEST_DIR/custom-lattice"
  run bash "$ENSURE" --mode worktree --bind tkt --id 23 --slug home-env
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "custom-lattice"
  unset LATTICE_HOME
}

@test "existing path that is a plain subdir of the main checkout is rejected" {
  mkdir -p "$MAIN/inner"
  run bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo --path "$MAIN/inner"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "not a worktree root"
}

@test "existing non-git directory at the worktree path is rejected" {
  mkdir -p "$TEST_DIR/repo.worktrees/tkt-7-demo"
  run bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "not a git worktree"
}

@test "another repository's worktree at the bound path is never adopted" {
  # Two repos share WORKTREE_ROOT (documented override) and bind the same
  # ticket branch. The second repo must refuse the first repo's worktree —
  # adopting it would silently route commits into the wrong repository.
  OTHER="$TEST_DIR/other"
  mkdir -p "$OTHER"
  git -C "$OTHER" init -q -b main
  git -C "$OTHER" config user.email lattice-test@example.invalid
  git -C "$OTHER" config user.name 'Lattice Test'
  git -C "$OTHER" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  SHARED="$TEST_DIR/shared-worktrees"
  (cd "$OTHER" && WORKTREE_ROOT="$SHARED" bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo >/dev/null)

  cd "$MAIN"
  run env WORKTREE_ROOT="$SHARED" bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "belongs to another repository"
}

@test "existing worktree on the wrong branch is rejected with a stale hint" {
  bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo >/dev/null
  WT="$TEST_DIR/repo.worktrees/tkt-7-demo"
  git -C "$WT" checkout -q --detach
  run bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "expected 'tkt-7-demo'"
}

@test "idempotent: re-running on existing correct worktree succeeds" {
  bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo >/dev/null
  run bash "$ENSURE" --mode worktree --bind tkt --id 7 --slug demo
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"ok": true'
  printf '%s\n' "$output" | grep -qF '"branch": "tkt-7-demo"'
}

@test "new date-shaped spc bind fails closed" {
  run bash "$ENSURE" --mode branch --bind spc --id 2026-07-27 --slug demo
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "date-shaped spc id is no longer accepted"
}

@test "branch-create race: concurrent same-bind create is adopted as reuse" {
  SHIM="$TEST_DIR/shim"
  mkdir -p "$SHIM"
  REAL_GIT="$(command -v git)"
  STATE="$TEST_DIR/race-state"
  # Simulate losing the show-ref -> git branch race: the first `git branch
  # tkt-38-race <oid>` finds the ref already created by a concurrent call.
  cat >"$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "branch" && "\$2" == "tkt-38-race" && ! -e "$STATE" ]]; then
  touch "$STATE"
  "$REAL_GIT" branch tkt-38-race "\$3" >/dev/null 2>&1
  exec "$REAL_GIT" "\$@"
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
  chmod +x "$SHIM/git"
  run env PATH="$SHIM:$PATH" bash "$ENSURE" --mode worktree --bind tkt --id 38 --slug race --base main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"reused_existing_branch": true'
  [ -z "$(printf '%s\n' "$output" | grep -F "could not create branch")" ]
}

@test "symlinked entrypoint resolves back to trusted install, not a consumer fake (tkt-239)" {
  # Place a fake _lattice-home.sh beside a symlink to ensure-workspace.sh.
  # With resolve_script_dir, SCRIPT_DIR_ENSURE resolves through the symlink
  # to the trusted repo scripts dir -> the REAL _lattice-home.sh is sourced
  # and the consumer fake is NOT (in-process RCE prevention).
  CONSUMER="$TEST_DIR/consumer/scripts"
  SENTINEL="$TEST_DIR/fake-home-sourced"
  mkdir -p "$CONSUMER"
  ln -s "$ENSURE" "$CONSUMER/ensure-workspace.sh"
  cat >"$CONSUMER/_lattice-home.sh" <<EOF
#!/usr/bin/env bash
printf 'fake\n' > "$SENTINEL"
lattice_profile() { printf 'strict\n'; }
EOF
  run bash "$CONSUMER/ensure-workspace.sh" --mode branch --bind tkt --id 240 --slug symtest
  [ "$status" -eq 0 ]
  [ ! -f "$SENTINEL" ]
}
