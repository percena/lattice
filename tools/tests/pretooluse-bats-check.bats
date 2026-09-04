#!/usr/bin/env bats
# tools/hooks/pretooluse-bats-check.py — optional maintainer PreToolUse hook
# (tkt-460 A5). Claude Code blocks a PreToolUse call only on exit 2; the first
# version exited 1 while printing BLOCKED, so the write went through.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HOOK="$REPO_ROOT/tools/hooks/pretooluse-bats-check.py"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ptu.XXXXXX")"
}

teardown() {
  rm -rf "$TEST_DIR"
}

payload() { # tool file content
  jq -cn --arg tool "$1" --arg fp "$2" --arg c "$3" '{tool_name:$tool,tool_input:{file_path:$fp,content:$c}}'
}

@test "tkt-460 A5: Write of a .bats file with a bare [[ ]] assertion exits 2 (blocks) and names the finding" {
  run bash -c "$(printf '%q' "$(payload Write "$TEST_DIR/x.bats" $'@test "t" {\n  [[ "$status" -eq 0 ]]\n}\n')" | sed 's/^/printf %s /') | python3 '$HOOK'"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "PreToolUse: BLOCKED"
}

@test "tkt-460 A5: Write of a clean .bats file exits 0" {
  run bash -c "printf '%s' '$(payload Write "$TEST_DIR/y.bats" $'@test "t" {\n  run true\n  [ "$status" -eq 0 ]\n}\n' | sed "s/'/'\\\\''/g")' | python3 '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "tkt-460 A5: non-.bats path and malformed payload always allow (exit 0, fail-open)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/a.sh\",\"content\":\"[[ 1 ]]\"}}' | python3 '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' 'not json' | python3 '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "tkt-460 A5: Edit that introduces a banned form on an existing .bats file exits 2" {
  printf '@test "t" {\n  run true\n  [ "$status" -eq 0 ]\n}\n' >"$TEST_DIR/z.bats"
  P=$(jq -cn --arg fp "$TEST_DIR/z.bats" '{tool_name:"Edit",tool_input:{file_path:$fp,old_string:"  [ \"$status\" -eq 0 ]",new_string:"  [[ \"$status\" -eq 0 ]]"}}')
  run bash -c "printf '%s' '$P' | python3 '$HOOK'"
  [ "$status" -eq 2 ]
}
