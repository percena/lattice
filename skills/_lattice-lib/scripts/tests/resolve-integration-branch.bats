#!/usr/bin/env bats
# Tests for resolve-integration-branch.sh: long-lived discovery + base pipeline.
# Uses a local bare origin (main + dev) so no GitHub network is required;
# gh default-branch lookup soft-fails to "main" and remote branches drive LL discovery.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export RIB="$REPO_ROOT/skills/_lattice-lib/scripts/resolve-integration-branch.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rib.XXXXXX")"
  ORIGIN="$TEST_DIR/origin.git"
  WORK="$TEST_DIR/work"
  # Bare origin with two long-lived branches: main + dev (dev ahead of main).
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  git -C "$WORK" config user.email lattice-test@example.invalid
  git -C "$WORK" config user.name 'Lattice Test'
  cd "$WORK"
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git branch -M main
  git checkout -q -b dev
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "dev work"
  git push -q origin main dev
  git checkout -q dev
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "user on dev (long-lived) → base=dev, source=user_branch" {
  run bash "$RIB" --repo-root "$WORK" --user-branch dev --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"recommended_base": "dev"'* ]]
  [[ "$output" == *'"base_source": "user_branch"'* ]]
}

@test "user on main (long-lived) → base=main, source=user_branch" {
  git checkout -q main
  run bash "$RIB" --repo-root "$WORK" --user-branch main --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"recommended_base": "main"'* ]]
  [[ "$output" == *'"base_source": "user_branch"'* ]]
}

@test "temp branch forked from dev → base=dev via fork-point" {
  git checkout -q -b tkt-42-demo dev
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feature"
  run bash "$RIB" --repo-root "$WORK" --user-branch tkt-42-demo --head tkt-42-demo --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"recommended_base": "dev"'* ]]
  [[ "$output" == *'"base_source": "fork_point"'* ]]
}

@test "temp branch forked from main → base=main via fork-point" {
  git checkout -q -b tkt-7-fix main
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "fix"
  run bash "$RIB" --repo-root "$WORK" --user-branch tkt-7-fix --head tkt-7-fix --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"recommended_base": "main"'* ]]
  [[ "$output" == *'"base_source": "fork_point"'* ]]
}

@test "long_lived set discovers main + dev from remotes" {
  run bash "$RIB" --repo-root "$WORK" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"long_lived": ['* ]]
  [[ "$output" == *"main"* ]]
  [[ "$output" == *"dev"* ]]
}

@test "config long_lived_patterns adds a custom long-lived branch" {
  mkdir -p "$WORK/.lattice"
  git checkout -q -b integration dev
  git push -q origin integration
  printf 'long_lived_patterns:\n  - integration\n' > "$WORK/.lattice/config.yaml"
  git checkout -q integration
  run bash "$RIB" --repo-root "$WORK" --user-branch integration --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"recommended_base": "integration"'* ]]
  [[ "$output" == *'"base_source": "user_branch"'* ]]
}

@test "release/* glob matches a release branch" {
  git checkout -q -b release/1.0 main
  git push -q origin release/1.0
  run bash "$RIB" --repo-root "$WORK" --user-branch release/1.0 --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"release/1.0"* ]]
  [[ "$output" == *'"recommended_base": "release/1.0"'* ]]
}

@test "no remote (pure local repo) does not crash; LL={main}, base=main" {
  LOCAL_ONLY="$TEST_DIR/local"
  mkdir -p "$LOCAL_ONLY"
  git -C "$LOCAL_ONLY" init -q -b main
  git -C "$LOCAL_ONLY" config user.email lattice-test@example.invalid
  git -C "$LOCAL_ONLY" config user.name 'Lattice Test'
  git -C "$LOCAL_ONLY" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run bash "$RIB" --repo-root "$LOCAL_ONLY" --user-branch main --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"recommended_base": "main"'* ]]
  [[ "$output" == *'"base_source": "user_branch"'* ]]
}
