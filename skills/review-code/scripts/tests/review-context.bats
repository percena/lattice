#!/usr/bin/env bats

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export REVIEW_CONTEXT="$REPO_ROOT/skills/review-code/scripts/review-context.py"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/review-context.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  REMOTE="$TEST_DIR/remote.git"
  git init -q --bare "$REMOTE"
  git init -q -b main "$MAIN"
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" config user.email test@example.com
  git -C "$MAIN" config user.name test
  git -C "$MAIN" commit -q --allow-empty -m main
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q -u origin main
  git -C "$MAIN" switch -q -c dev
  printf '%s\n' dev >"$MAIN/dev.txt"
  git -C "$MAIN" add dev.txt
  git -C "$MAIN" commit -q -m dev-advance
  git -C "$MAIN" push -q -u origin dev
  git -C "$MAIN" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  mkdir -p "$TEST_DIR/bin"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "GitHub dev default beats stale origin HEAD and clean dev has no changes" {
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' dev
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run bash -c "cd '$MAIN' && PATH='$TEST_DIR/bin:$PATH' python3 '$REVIEW_CONTEXT' --branch HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'- Base: `origin/dev`'* ]]
  [[ "$output" == *'- Has changes: `no`'* ]]
}

@test "explicit base still wins over GitHub metadata" {
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' dev
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run bash -c "cd '$MAIN' && PATH='$TEST_DIR/bin:$PATH' python3 '$REVIEW_CONTEXT' --branch HEAD --base origin/main"
  [ "$status" -eq 0 ]
  [[ "$output" == *'- Base: `origin/main`'* ]]
  [[ "$output" == *'- Has changes: `yes`'* ]]
}

@test "--pr without gh on PATH is a clean error, not a traceback" {
  NOGH="$TEST_DIR/nogh-bin"
  mkdir -p "$NOGH"
  ln -s "$(command -v git)" "$NOGH/git"
  ln -s "$(command -v python3)" "$NOGH/python3"
  run bash -c "cd '$MAIN' && PATH='$NOGH' python3 '$REVIEW_CONTEXT' --pr 5"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: gh pr view 5"* ]]
  [[ "$output" == *"gh is not available"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "configured base wins over GitHub metadata" {
  mkdir -p "$MAIN/.lattice"
  printf '%s\n' 'base_branch: main' >"$MAIN/.lattice/config.yaml"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' dev
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run bash -c "cd '$MAIN' && PATH='$TEST_DIR/bin:$PATH' python3 '$REVIEW_CONTEXT' --branch HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'- Base: `origin/main`'* ]]
  [[ "$output" == *'- Has changes: `yes`'* ]]
}
