#!/usr/bin/env bats
# bats: assert-shippable-cwd + check-base-residue

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export REPO_ROOT
  export ASSERT="$REPO_ROOT/skills/_lattice-lib/scripts/assert-shippable-cwd.sh"
  export RESIDUE="$REPO_ROOT/skills/_lattice-lib/scripts/check-base-residue.sh"
  export INIT="$REPO_ROOT/skills/_lattice-lib/scripts/lattice-init.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/assert-cwd.XXXXXX")"
  export TEST_DIR
  git -C "$TEST_DIR" init -b main >/dev/null 2>&1
  git -C "$TEST_DIR" config user.email lattice-test@example.invalid
  git -C "$TEST_DIR" config user.name 'Lattice Test'
  git -C "$TEST_DIR" config user.email "test@example.com"
  git -C "$TEST_DIR" config user.name "test"
  echo x >"$TEST_DIR/README"
  git -C "$TEST_DIR" add README
  git -C "$TEST_DIR" commit -m init >/dev/null
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "assert fails on team base main clone" {
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --json"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false' || printf '%s\n' "$output" | grep -qF '"ok":false'
  printf '%s\n' "$output" | grep -qF team_base_checkout
}

@test "explicit clean base-direct escape passes and records reason" {
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --json --allow-base-write --reason 'user explicitly requested direct base commit'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"base_direct_escape": true'
  printf '%s\n' "$output" | grep -qF '"on_team_base": true'
  printf '%s\n' "$output" | grep -qF '"escape_reason": "user explicitly requested direct base commit"'
}

@test "base-direct escape refuses a dirty starting tree" {
  echo dirty >"$TEST_DIR/dirty.txt"
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --allow-base-write --reason 'user authorized'"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "clean starting tree"
}

@test "GitHub default branch metadata wins over stale origin HEAD" {
  git -C "$TEST_DIR" branch dev
  git -C "$TEST_DIR" remote add origin "$TEST_DIR"
  git -C "$TEST_DIR" update-ref refs/remotes/origin/dev refs/heads/dev
  git -C "$TEST_DIR" update-ref refs/remotes/origin/main refs/heads/main
  git -C "$TEST_DIR" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' dev
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run bash -c "cd '$TEST_DIR' && PATH='$TEST_DIR/bin:$PATH' bash '$ASSERT' --json"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"default_base": "dev"'
  printf '%s\n' "$output" | grep -qF '"base_source": "gh-default"'
}

@test "config without base_branch falls through and still emits structured output" {
  mkdir -p "$TEST_DIR/.lattice"
  printf '%s\n' 'profile: strict' >"$TEST_DIR/.lattice/config.yaml"
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --json"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false'
  printf '%s\n' "$output" | grep -qF '"default_base": "main"'
  printf '%s\n' "$output" | grep -qF '"base_source": "fallback"'
  printf '%s\n' "$output" | grep -qF team_base_checkout
}

@test "explicit fully qualified custom base is still recognized as team base" {
  git -C "$TEST_DIR" branch release
  git -C "$TEST_DIR" checkout release >/dev/null
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --json --base refs/heads/release"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF team_base_checkout
  printf '%s\n' "$output" | grep -qF '"default_base": "refs/heads/release"'
}

@test "assert passes on feature branch of main clone (light profile)" {
  mkdir -p "$TEST_DIR/.lattice"
  printf '%s\n' 'profile: light' >"$TEST_DIR/.lattice/config.yaml"
  git -C "$TEST_DIR" checkout -b tkt-9-demo >/dev/null
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT'"
  [ "$status" -eq 0 ]
}

@test "assert fails on feature branch of main clone under strict profile" {
  mkdir -p "$TEST_DIR/.lattice"
  printf '%s\n' 'profile: strict' >"$TEST_DIR/.lattice/config.yaml"
  git -C "$TEST_DIR" checkout -b tkt-9-demo >/dev/null
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --json"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false' || printf '%s\n' "$output" | grep -qF '"ok":false'
  printf '%s\n' "$output" | grep -qF non_base_on_main_clone
}

@test "non-base main-clone strict escape via --allow-base-write --reason passes" {
  mkdir -p "$TEST_DIR/.lattice"
  printf '%s\n' 'profile: strict' >"$TEST_DIR/.lattice/config.yaml"
  git -C "$TEST_DIR" add .lattice && git -C "$TEST_DIR" commit -m cfg >/dev/null
  git -C "$TEST_DIR" checkout -b tkt-9-demo >/dev/null
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --json --allow-base-write --reason 'user-authorized: quick fix'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"base_direct_escape": true'
  printf '%s\n' "$output" | grep -qF authorized_nonbase_direct
  printf '%s\n' "$output" | grep -qF '"on_team_base": false'
}

@test "assert fails on detached HEAD on main clone" {
  git -C "$TEST_DIR" checkout --detach >/dev/null 2>&1
  run bash -c "cd '$TEST_DIR' && bash '$ASSERT' --json"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok": false' || printf '%s\n' "$output" | grep -qF '"ok":false'
  printf '%s\n' "$output" | grep -qF detached_or_empty_on_main_clone
}

@test "assert passes inside linked worktree" {
  git -C "$TEST_DIR" branch tkt-9-demo main
  WT="$TEST_DIR.worktrees/tkt-9-demo"
  mkdir -p "$(dirname "$WT")"
  git -C "$TEST_DIR" worktree add "$WT" tkt-9-demo >/dev/null
  run bash -c "cd '$WT' && bash '$ASSERT'"
  [ "$status" -eq 0 ]
  git -C "$TEST_DIR" worktree remove "$WT" >/dev/null 2>&1 || true
}

@test "check-base-residue detects dirty .lattice on main" {
  bash "$INIT" --root "$TEST_DIR" --no-write-gitignore 2>/dev/null || bash "$INIT" --root "$TEST_DIR" >/dev/null
  # leave uncommitted binder
  mkdir -p "$TEST_DIR/.lattice/tickets/tkt-1-x"
  echo dirty >"$TEST_DIR/.lattice/tickets/tkt-1-x/README.md"
  run bash "$RESIDUE" --main-root "$TEST_DIR" --json --strict
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"has_residue": true' || printf '%s\n' "$output" | grep -qF '"has_residue":true'
}

@test "check-base-residue clean when no porcelain under .lattice" {
  bash "$INIT" --root "$TEST_DIR" >/dev/null
  git -C "$TEST_DIR" add -A
  git -C "$TEST_DIR" commit -m lattice --allow-empty >/dev/null 2>&1 || \
    git -C "$TEST_DIR" commit -m lattice >/dev/null
  # commit .lattice so porcelain clean for lattice paths
  git -C "$TEST_DIR" add .lattice .gitignore 2>/dev/null || true
  git -C "$TEST_DIR" commit -m "chore: lattice" >/dev/null 2>&1 || true
  run bash "$RESIDUE" --main-root "$TEST_DIR" --json --strict
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"has_residue": false' || printf '%s\n' "$output" | grep -qF '"has_residue":false'
}

@test "lattice-init does not double-append gitignore when lattice rules exist without marker" {
  : >"$TEST_DIR/.gitignore"
  cat >>"$TEST_DIR/.gitignore" <<'EOF'
.lattice/lineage/
.lattice/.ids/
EOF
  bash "$INIT" --root "$TEST_DIR" --write-gitignore >/dev/null
  count=$(grep -c 'lineage/' "$TEST_DIR/.gitignore" || true)
  [ "$count" -eq 1 ]
}

@test "check-base-residue detects dirty Lattice .gitignore only" {
  bash "$INIT" --root "$TEST_DIR" --write-gitignore >/dev/null
  git -C "$TEST_DIR" add .lattice .gitignore
  git -C "$TEST_DIR" commit -m "chore: lattice" >/dev/null
  # mutate tracked Lattice gitignore without touching .lattice
  echo "# agent dirt" >>"$TEST_DIR/.gitignore"
  run bash "$RESIDUE" --main-root "$TEST_DIR" --json --strict
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"has_residue": true' || printf '%s\n' "$output" | grep -qF '"has_residue":true'
  printf '%s\n' "$output" | grep -qF '.gitignore'
}

@test "assert --json without python3 fails cleanly, not 127 at emission" {
  FAKE_BIN="$TEST_DIR/nopython"
  mkdir -p "$FAKE_BIN"
  for tool in bash git grep sed tr head cat dirname basename; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$p" "$FAKE_BIN/$tool"
  done
  run bash -c "cd '$TEST_DIR' && export PATH='$FAKE_BIN' && exec bash '$ASSERT' --json"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "python3 is required"
}

@test "check-base-residue --json without python3 fails cleanly" {
  FAKE_BIN="$TEST_DIR/nopython"
  mkdir -p "$FAKE_BIN"
  for tool in bash git grep sed tr head cat dirname basename; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$p" "$FAKE_BIN/$tool"
  done
  run bash -c "export PATH='$FAKE_BIN' && exec bash '$RESIDUE' --main-root '$TEST_DIR' --json"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "python3 is required"
}

@test "ensure-lattice --json stays valid when init prints stderr warnings" {
  ENSURE="$REPO_ROOT/skills/_lattice-lib/scripts/ensure-lattice.sh"
  # --sync-labels may warn on stderr; ensure keeps stderr separate so stdout is pure JSON
  # (bats $output mixes streams — capture stdout only)
  run bash -c "bash '$ENSURE' --root '$TEST_DIR' --json --sync-labels 2>/dev/null"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("ok") is True'
}
