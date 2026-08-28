#!/usr/bin/env bats
# End-to-end tests for intercept-git-branch-create.sh PreToolUse hook.
# Builds a real git repo (main clone) + a linked worktree so the location
# gate (main clone vs worktree) is exercised truthfully.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/intercept-git-branch-create.sh"

  # Fixture: a throwaway main clone with a base branch + a linked worktree.
  MAIN_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/main-clone"
  WORK_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/wt"
  git init -q "$MAIN_ROOT"
  git -C "$MAIN_ROOT" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN_ROOT" config user.email t@t.test
  git -C "$MAIN_ROOT" config user.name t
  git -C "$MAIN_ROOT" commit -q --allow-empty -m init
  # an existing non-base branch (for switch-existing tests)
  git -C "$MAIN_ROOT" branch feat-existing
  # a linked worktree on a feature branch
  git -C "$MAIN_ROOT" worktree add -q "$WORK_ROOT" -b feat-wt-branch
}

teardown() {
  git -C "$MAIN_ROOT" worktree remove --force "$WORK_ROOT" 2>/dev/null || true
  rm -rf "$MAIN_ROOT" "$WORK_ROOT" 2>/dev/null || true
}

# pipe a PreToolUse JSON payload (with cwd) into the hook
run_hook() {  # <cwd> <command>
  local cwd="$1" cmd="$2"
  jq -cn --arg c "$cmd" --arg w "$cwd" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}' \
    | bash "$HOOK_SCRIPT" 2>&1
}

# ============================== main clone: BLOCK ==============================

@test "main clone: blocks git checkout -b (unbound)" {
  run run_hook "$MAIN_ROOT" 'git checkout -b tmp-fix'
  [ "$status" -eq 2 ]
  [[ "$output" == *"blocked in the main clone"* ]]
  [[ "$output" == *ensure-workspace* ]]
}

@test "main clone: blocks git checkout -b (BOUND name — the recorded drift)" {
  run run_hook "$MAIN_ROOT" 'git checkout -b tkt-8-foo'
  [ "$status" -eq 2 ]
  [[ "$output" == *"blocked"* ]]
}

@test "main clone: blocks git switch -c" {
  run run_hook "$MAIN_ROOT" 'git switch -c tmp'
  [ "$status" -eq 2 ]
}

@test "main clone: blocks git branch <create>" {
  run run_hook "$MAIN_ROOT" 'git branch tmp'
  [ "$status" -eq 2 ]
}

@test "main clone: blocks two-step bypass (git branch tmp; switch tmp)" {
  run run_hook "$MAIN_ROOT" 'git branch tmp'
  [ "$status" -eq 2 ]
  run run_hook "$MAIN_ROOT" 'git switch tmp'
  # tmp wasn't created (create was blocked), so switch targets a non-existent
  # branch -> fail-open (file-like). The create step is the gate; this asserts
  # the create was blocked.
}

@test "main clone: blocks switch to existing non-base branch" {
  run run_hook "$MAIN_ROOT" 'git switch feat-existing'
  [ "$status" -eq 2 ]
}

@test "main clone: blocks checkout of existing non-base branch" {
  run run_hook "$MAIN_ROOT" 'git checkout feat-existing'
  [ "$status" -eq 2 ]
}

# ============================== main clone: ALLOW ==============================

@test "main clone: allows switch to base (main)" {
  run run_hook "$MAIN_ROOT" 'git switch main'
  [ "$status" -eq 0 ]
}

@test "main clone: allows switch to base (master)" {
  run run_hook "$MAIN_ROOT" 'git switch master'
  [ "$status" -eq 0 ]
}

@test "main clone: allows git status" {
  run run_hook "$MAIN_ROOT" 'git status'
  [ "$status" -eq 0 ]
}

@test "main clone: allows branch list (git branch -a)" {
  run run_hook "$MAIN_ROOT" 'git branch -a'
  [ "$status" -eq 0 ]
}

@test "main clone: allows branch delete (git branch -d)" {
  run run_hook "$MAIN_ROOT" 'git branch -d feat-existing'
  [ "$status" -eq 0 ]
}

@test "main clone: allows file restore (git checkout -- file)" {
  run run_hook "$MAIN_ROOT" 'git checkout -- file.txt'
  [ "$status" -eq 0 ]
}

@test "main clone: allows ensure-workspace invocation (blessed entry)" {
  run run_hook "$MAIN_ROOT" 'bash /x/ensure-workspace.sh --mode worktree --bind tkt --id 8 --slug foo'
  [ "$status" -eq 0 ]
}

# ============================== worktree: ALLOW all ==============================

@test "worktree: allows git checkout -b" {
  run run_hook "$WORK_ROOT" 'git checkout -b tmp-in-wt'
  [ "$status" -eq 0 ]
}

@test "worktree: allows git switch -c" {
  run run_hook "$WORK_ROOT" 'git switch -c foo'
  [ "$status" -eq 0 ]
}

# ============================== fail-open ==============================

@test "non-Bash tool is allowed (Read)" {
  run bash -c "jq -cn '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/etc/hosts\"}}' | '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
}

@test "non-git Bash command is allowed" {
  run run_hook "$MAIN_ROOT" 'ls -la'
  [ "$status" -eq 0 ]
}
