#!/usr/bin/env bats
# Tests for check-pr-context.sh: exact-ref already_pushed match,
# gh preflight, default-branch fallback surfacing. Stubbed gh, local bare remote.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export CTX="$REPO_ROOT/skills/create-pr/scripts/check-pr-context.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pr-ctx.XXXXXX")"
  REMOTE="$TEST_DIR/remote.git"
  MAIN="$TEST_DIR/repo"
  git init -q --bare "$REMOTE"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$MAIN" remote add origin "$REMOTE"
  git -C "$MAIN" push -q -u origin main

  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${GH_FAIL:-}" == "true" ]]; then exit 1; fi
if [[ "$*" == *visibility* ]]; then echo "PUBLIC"; exit 0; fi
if [[ "$*" == *defaultBranchRef* ]]; then
  if [[ "${GH_DEFAULT_FAIL:-}" == "true" ]]; then exit 1; fi
  echo "${GH_DEFAULT_BRANCH:-dev}"
  exit 0
fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  cd "$MAIN"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "already_pushed requires an exact ref: bar/foo does not match foo" {
  git checkout -q -b bar/foo
  git push -q origin bar/foo
  git checkout -q -b foo
  run bash "$CTX"
  [ "$status" -eq 0 ]
  last=$(printf '%s\n' "$output" | grep '^{' | tail -1)
  printf '%s' "$last" | jq -e '.branch == "foo" and .already_pushed == false'
}

@test "already_pushed true for an exactly pushed branch" {
  git checkout -q -b feature-x
  git push -q origin feature-x
  run bash "$CTX"
  [ "$status" -eq 0 ]
  last=$(printf '%s\n' "$output" | grep '^{' | tail -1)
  printf '%s' "$last" | jq -e '.already_pushed == true'
}

@test "default branch from GitHub is surfaced with source github" {
  run bash "$CTX"
  [ "$status" -eq 0 ]
  last=$(printf '%s\n' "$output" | grep '^{' | tail -1)
  printf '%s' "$last" | jq -e '.default_branch == "dev" and .default_branch_source == "github"'
}

@test "gh default-branch failure falls back to main with a loud source + warning" {
  GH_DEFAULT_FAIL=true run bash "$CTX"
  [ "$status" -eq 0 ]
  last=$(printf '%s\n' "$output" | grep '^{' | tail -1)
  printf '%s' "$last" | jq -e '.default_branch == "main" and .default_branch_source == "fallback"'
  printf '%s\n' "$output" | grep -qF "could not resolve the default branch"
}

@test "missing gh fails the preflight with an error" {
  NOGH_BIN="$TEST_DIR/nogh-bin"
  mkdir -p "$NOGH_BIN"
  for tool in git jq bash awk sed grep cat; do
    p="$(command -v "$tool" 2>/dev/null)" && ln -sf "$p" "$NOGH_BIN/$tool" || true
  done
  run env PATH="$NOGH_BIN" bash "$CTX"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "gh not found"
}
