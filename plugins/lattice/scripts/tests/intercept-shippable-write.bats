#!/usr/bin/env bats
# End-to-end tests for intercept-shippable-write.sh PreToolUse hook (L3).

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/intercept-shippable-write.sh"

  MAIN_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/main"
  git init -q "$MAIN_ROOT"
  git -C "$MAIN_ROOT" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN_ROOT" config user.email t@t.test
  git -C "$MAIN_ROOT" config user.name t
  git -C "$MAIN_ROOT" commit -q --allow-empty -m init
  mkdir -p "$MAIN_ROOT/.lattice/specs" "$MAIN_ROOT/.lattice/tickets" \
           "$MAIN_ROOT/.lattice/reviews" "$MAIN_ROOT/docs/adr" "$MAIN_ROOT/src"
  echo code >"$MAIN_ROOT/src/app.py"
  printf 'profile: strict\n' >"$MAIN_ROOT/.lattice/config.yaml"
  git -C "$MAIN_ROOT" add -A
  git -C "$MAIN_ROOT" commit -q -m files
  git -C "$MAIN_ROOT" worktree add -q "$MAIN_ROOT.wt" -b feat-wt
}

teardown() {
  git -C "$MAIN_ROOT" worktree remove --force "$MAIN_ROOT.wt" 2>/dev/null || true
  rm -rf "$MAIN_ROOT" "$MAIN_ROOT.wt" 2>/dev/null || true
}

# pipe a Write payload (cwd + file_path) into the hook
run_write() {  # <cwd> <file_path>
  local cwd="$1" path="$2"
  jq -cn --arg f "$path" --arg w "$cwd" \
    '{tool_name:"Write",tool_input:{file_path:$f},cwd:$w}' \
    | bash "$HOOK_SCRIPT" 2>&1
}

# ===================== main base: BLOCK =====================

@test "base: blocks .lattice/specs write" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/specs/spc-1.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"shippable write blocked"* ]]
}

@test "base: blocks .lattice/tickets write" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/tickets/tkt-1/R.md"
  [ "$status" -eq 2 ]
}

@test "base: blocks tracked product code write" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/src/app.py"
  [ "$status" -eq 2 ]
}

# ===================== exemptions: ALLOW on base =====================

@test "base: allows .lattice/reviews write (exempt)" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/reviews/rev-1.md"
  [ "$status" -eq 0 ]
}

@test "base: allows docs/adr write (exempt)" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/docs/adr/006-x.md"
  [ "$status" -eq 0 ]
}

# ===================== fail-open: ALLOW =====================

@test "allows new untracked file outside gated L0 (scratch)" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/src/new_untracked.py"
  [ "$status" -eq 0 ]
}

@test "allows write outside repo (/tmp)" {
  run run_write "$MAIN_ROOT" "${BATS_TEST_TMPDIR:-/tmp}/scratch.txt"
  [ "$status" -eq 0 ]
}

@test "allows non-Write/Edit tool (Read)" {
  run bash -c "jq -cn '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/etc/hosts\"}}' | '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
}

# ===================== worktree: ALLOW all =====================

@test "worktree: allows .lattice/specs write" {
  run run_write "$MAIN_ROOT.wt" "$MAIN_ROOT.wt/.lattice/specs/spc-3.md"
  [ "$status" -eq 0 ]
}

@test "worktree: allows tracked product code write" {
  run run_write "$MAIN_ROOT.wt" "$MAIN_ROOT.wt/src/app.py"
  [ "$status" -eq 0 ]
}

# ===================== non-base branch in main clone (strict): BLOCK =====================

@test "strict: blocks .lattice/specs write on non-base branch in main clone" {
  git -C "$MAIN_ROOT" checkout -q -b drift-branch
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/specs/spc-2.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *non_base_on_main_clone* ]]
}
