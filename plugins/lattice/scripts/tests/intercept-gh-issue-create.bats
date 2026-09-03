#!/usr/bin/env bats
# Tests for intercept-gh-issue-create.sh PreToolUse hook

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/intercept-gh-issue-create.sh"

  TEST_SESSION="intercept-gh-issue-create-test-${BATS_TEST_NUMBER}-$$"
  export ACTIVATED_SKILLS_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/activated-skills"
  mkdir -p "$ACTIVATED_SKILLS_ROOT"
  TEST_MARKER_DIR="${ACTIVATED_SKILLS_ROOT}/${TEST_SESSION}"
  export LATTICE_HOOK_MODE=strict
}

teardown() {
  rm -rf "$TEST_MARKER_DIR"
}

run_hook() {
  echo "$1" | "$HOOK_SCRIPT" 2>&1
}

run_advisory_hook() {
  echo "$1" | LATTICE_HOOK_MODE=advisory "$HOOK_SCRIPT" 2>&1
}

payload_for_command() {
  jq -cn --arg session_id "$TEST_SESSION" --arg command "$1" \
    '{tool_name:"Bash",session_id:$session_id,tool_input:{command:$command}}'
}

# ============================================================
# Fast path — non-Bash tools pass through
# ============================================================

@test "allows non-Bash tools (Read)" {
  run run_hook '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'
  [ "$status" -eq 0 ]
}

@test "allows non-Bash tools (Edit)" {
  run run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test"}}'
  [ "$status" -eq 0 ]
}

# ============================================================
# Strict mode — blocks bare gh issue create
# ============================================================

@test "blocks bare gh issue create in strict mode" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create\"}}"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "create-tickets"
}

@test "blocks gh issue create with flags" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create --title foo --body bar\"}}"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "create-tickets"
}

@test "blocks gh issue create with --label flag" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create --title test --label bug,P1\"}}"
  [ "$status" -eq 2 ]
}

@test "blocks gh issue create with repo flag placements" {
  for command in \
    "gh -R owner/repo issue create" \
    "gh --repo owner/repo issue create" \
    "gh issue -R owner/repo create"; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"${command}\"}}"
    [ "$status" -eq 2 ]
  done
}

# ============================================================
# Advisory mode — allows with guidance
# ============================================================

@test "advisory mode allows bare gh issue create with guidance" {
  run run_advisory_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create\"}}"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "create-tickets"
  printf '%s\n' "$output" | grep -qF "Hook mode: advisory"
}

@test "unknown hook mode degrades to strict" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create\"}}' | LATTICE_HOOK_MODE=unexpected '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "Hook mode: strict"
}

# ============================================================
# Marker allows — create-tickets skill active
# ============================================================

@test "allows gh issue create when create-tickets marker present" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-tickets"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create --title test\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh issue create when lattice:create-tickets marker present" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/lattice:create-tickets"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create --title test\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh issue create when create-spec marker present (alt skill)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-spec"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create --title test\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh issue create when lattice:create-spec marker present (alt skill)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/lattice:create-spec"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue create --title test\"}}"
  [ "$status" -eq 0 ]
}

# ============================================================
# Non-matching commands pass through
# ============================================================

@test "allows gh issue list (not create)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue list\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh issue view" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh issue view 42\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh pr create (different verb — handled by its own hook)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}"
  [ "$status" -eq 0 ]
}
