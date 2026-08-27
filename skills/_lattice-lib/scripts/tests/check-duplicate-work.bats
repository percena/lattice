#!/usr/bin/env bats
# Tests for check-duplicate-work.sh: fail-loud coverage gaps, CJK OR-branch,
# arg guards, and the always-exit-0 advisory contract. GitHub traffic goes
# through a fake `gh` on PATH (stamp-pr-open.bats style). bats 1.2.x has no
# BATS_TEST_TMPDIR: temp dirs are self-managed via mktemp/teardown.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export CDW="$REPO_ROOT/skills/_lattice-lib/scripts/check-duplicate-work.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cdw.XXXXXX")"
  # A real git repo so the worktree surface runs (branch "main", no overlap
  # with any test title).
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  git -C "$REPO" commit -q --allow-empty -m init
  ISSUES_FIXTURE="$TEST_DIR/issues.json"
  PRS_FIXTURE="$TEST_DIR/prs.json"
  printf '[]' >"$ISSUES_FIXTURE"
  printf '[]' >"$PRS_FIXTURE"
  write_fake_gh
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Fake gh: answers issue/pr list from test fixtures; repo view gives a slug.
write_fake_gh() {
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view")  printf '%s\n' 'acme/repo' ;;
  "issue list") cat "$ISSUES_FIXTURE" ;;
  "pr list")    cat "$PRS_FIXTURE" ;;
  *)            exit 1 ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/gh"
}

# Fake gh that fails every invocation (network down / bad auth).
write_failing_gh() {
  mkdir -p "$TEST_DIR/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$TEST_DIR/bin/gh"
  chmod +x "$TEST_DIR/bin/gh"
}

# PATH with everything the script needs EXCEPT jq, so `command -v jq` fails.
# (A PATH prefix cannot hide a real binary; a restricted PATH can.)
make_jqless_path() {
  mkdir -p "$TEST_DIR/rbin"
  local tool src
  for tool in bash git grep sed awk tr cat env python3; do
    src="$(command -v "$tool" 2>/dev/null || true)"
    [ -n "$src" ] && ln -s "$src" "$TEST_DIR/rbin/$tool"
  done
  ln -s "$TEST_DIR/bin/gh" "$TEST_DIR/rbin/gh"
}

run_cdw() {
  cd "$REPO"
  run env PATH="$TEST_DIR/bin:$PATH" \
    ISSUES_FIXTURE="$ISSUES_FIXTURE" PRS_FIXTURE="$PRS_FIXTURE" \
    bash "$CDW" "$@"
}

@test "ASCII token match: >=2 shared tokens flags the issue" {
  printf '%s' '[{"number":41,"title":"fix login flow tokens","url":"https://github.com/acme/repo/issues/41"}]' >"$ISSUES_FIXTURE"
  run_cdw --title "fix login flow" --repository acme/repo --skip-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING 1 possible overlap(s)"* ]]
  [[ "$output" == *"issue #41: fix login flow tokens"* ]]
}

@test "ASCII no-match: <2 shared tokens reports OK with surfaces counted" {
  printf '%s' '[{"number":42,"title":"docs overhaul sweep","url":"https://github.com/acme/repo/issues/42"}]' >"$ISSUES_FIXTURE"
  run_cdw --title "fix login flow" --repository acme/repo --skip-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK no possible overlap found (2 surfaces checked)"* ]]
  [[ "$output" != *"WARNING"* ]]
  [[ "$output" != *"coverage gap"* ]]
}

@test "CJK OR-branch: shared CJK run >=3 chars matches with zero shared tokens" {
  printf '%s' '[{"number":43,"title":"重构登录流程模块","url":"https://github.com/acme/repo/issues/43"}]' >"$ISSUES_FIXTURE"
  run_cdw --title "登录流程改进" --repository acme/repo --skip-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING 1 possible overlap(s)"* ]]
  [[ "$output" == *"issue #43"* ]]
}

@test "CJK non-match: shared run shorter than 3 chars stays OK" {
  printf '%s' '[{"number":44,"title":"流程审计系统","url":"https://github.com/acme/repo/issues/44"}]' >"$ISSUES_FIXTURE"
  run_cdw --title "登录流程" --repository acme/repo --skip-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK no possible overlap found"* ]]
  [[ "$output" != *"WARNING"* ]]
}

@test "missing jq: every surface reports a coverage gap, never OK" {
  make_jqless_path
  cd "$REPO"
  run env PATH="$TEST_DIR/rbin" \
    ISSUES_FIXTURE="$ISSUES_FIXTURE" PRS_FIXTURE="$PRS_FIXTURE" \
    bash "$CDW" --title "fix login flow" --repository acme/repo --skip-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage gap: open-issues unavailable (jq missing)"* ]]
  [[ "$output" == *"coverage gap: worktrees unavailable (jq missing)"* ]]
  [[ "$output" == *"INCONCLUSIVE"* ]]
  [[ "$output" != *"OK no possible overlap"* ]]
}

@test "gh failure: remote surfaces report coverage gaps, never OK" {
  write_failing_gh
  run_cdw --title "fix login flow" --repository acme/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage gap: open-issues unavailable (gh issue list failed)"* ]]
  [[ "$output" == *"coverage gap: open-prs unavailable (gh pr list failed)"* ]]
  [[ "$output" == *"INCONCLUSIVE 2 coverage gap(s)"* ]]
  [[ "$output" != *"OK no possible overlap"* ]]
}

@test "gh failure with --json: status coverage_gap and gaps carried in JSON" {
  write_failing_gh
  run_cdw --title "fix login flow" --repository acme/repo --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "coverage_gap"'
  printf '%s' "$output" | jq -e '.coverage_gaps | length == 2'
  printf '%s' "$output" | jq -e '.coverage_gaps[0] | contains("gh issue list failed")'
  printf '%s' "$output" | jq -e '.surfaces_checked == 1'
}

@test "clean --json keeps clean status with empty coverage_gaps" {
  run_cdw --title "fix login flow" --repository acme/repo --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.status == "clean"'
  printf '%s' "$output" | jq -e '.coverage_gaps == []'
  printf '%s' "$output" | jq -e '.total_overlaps == 0'
  printf '%s' "$output" | jq -e '.surfaces_checked == 3'
}

@test "--title with no value: advisory usage, exit 0 (no unbound variable)" {
  run_cdw --title
  [ "$status" -eq 0 ]
  [[ "$output" == *"--title requires a value"* ]]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "worktree surface: sibling worktree branch with shared tokens is flagged" {
  git -C "$REPO" worktree add -q "$TEST_DIR/wt-login-flow" -b fix-login-flow
  run_cdw --title "fix login flow" --repository acme/repo --skip-remote
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"worktree: fix-login-flow"* ]]
}
