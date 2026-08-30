#!/usr/bin/env bats
# Tests for intercept-gh-pr-merge.sh PreToolUse hook

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/intercept-gh-pr-merge.sh"
  TEST_SESSION="intercept-gh-pr-merge-test-${BATS_TEST_NUMBER}-$$"
  export ACTIVATED_SKILLS_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/activated-skills"
  mkdir -p "$ACTIVATED_SKILLS_ROOT"
  TEST_MARKER_DIR="${ACTIVATED_SKILLS_ROOT}/${TEST_SESSION}"
  # Batch-work merge gate (spc-187 A1): isolate the gate from the real repo so
  # existing tests are unaffected by repo MAIN state. Tests that exercise the
  # batch gate create the marker/flag inside this home.
  export LATTICE_BATCH_GATE_HOME="${BATS_TEST_TMPDIR:-$(mktemp -d)}/batch-gate-home"
  mkdir -p "$LATTICE_BATCH_GATE_HOME"
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

@test "advisory is the product default and allows bare gh pr merge with guidance" {
  run run_advisory_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "recommended path"
  printf '%s\n' "$output" | grep -qF "Hook mode: advisory"
}

@test "unknown hook mode degrades to advisory" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}' | LATTICE_HOOK_MODE=unexpected '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "Hook mode: advisory"
}

@test "allows non-Bash tools (Read)" {
  run run_hook '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'
  [ "$status" -eq 0 ]
}

@test "blocks bare gh pr merge" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "finish-work"
}

@test "blocks gh pr merge with flags" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 3 --squash --delete-branch\"}}"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "finish-work"
}

@test "blocks documented repository flag placements around pr" {
  for command in \
    "gh -R owner/repo pr merge 3" \
    "gh --repo owner/repo pr merge 3" \
    "gh --repo=owner/repo pr merge 3" \
    "gh pr -R owner/repo merge 3" \
    "gh pr --repo owner/repo merge 3"; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"${command}\"}}"
    [ "$status" -eq 2 ]
  done
}

@test "advisory notices repository-flag merge variants" {
  run run_advisory_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh -R owner/repo pr merge 3\"}}"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "recommended path"
}

@test "allows phrase inside single-quoted string" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo 'gh pr merge'\"}}"
  [ "$status" -eq 0 ]
}

@test "blocks gh pr merge in backtick command substitution" {
  for command in \
    'echo `gh pr merge 1`' \
    'x=`gh pr merge 1 --squash`'; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"${command}\"}}"
    [ "$status" -eq 2 ]
  done
}

@test "blocks backtick merge substitution inside double quotes" {
  command='x="`gh pr merge 1`"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 2 ]
}

@test "blocks \$(gh pr merge 1) substitution inside double quotes" {
  # $(...) executes inside double quotes; the normalizer must surface it rather
  # than collapsing the whole quoted span to a placeholder.
  command='echo "see: $(gh pr merge 1) done"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 2 ]
}

@test "blocks merge after a quoted opening paren inside \$(...)" {
  command='echo "$(printf "("; gh pr merge 1)"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 2 ]
}

@test "allows merge text after a quoted closing paren inside \$(...)" {
  command='echo "$(printf ")") gh pr merge 1 "'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 0 ]
}

@test "allows escaped \$(...) that only prints gh pr merge text" {
  command='echo "\$(gh pr merge 1)"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 0 ]
}

@test "allows escaped backticks that only print gh pr merge text" {
  command='echo \`gh pr merge 1\`'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 0 ]
}

@test "allows when finish-work marker present and no transcript" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/finish-work"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 0 ]
}

@test "allows when lattice:finish-work marker present" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/lattice:finish-work"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1 --squash\"}}"
  [ "$status" -eq 0 ]
}

@test "marker + foreign /foo:finish-work slash is not Lattice activation -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/finish-work"
  tf="$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/merge-transcript.XXXXXX.jsonl")"
  printf '%s\n' \
    '{"uuid":"m1","parentUuid":null,"type":"user","message":{"role":"user","content":"/foo:finish-work"}}' \
    '{"uuid":"m2","parentUuid":"m1","type":"user","message":{"role":"user","content":"go"}}' \
    >"$tf"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
}

@test "fail-open without session_id" {
  run run_hook '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}'
  [ "$status" -eq 0 ]
}

@test "fails open (allows) when activated-skills-root.sh resolver is missing" {
  ISOLATED="${BATS_TEST_TMPDIR:-$(mktemp -d)}/isolated/hooks"
  mkdir -p "$ISOLATED"
  cp "$HOOK_SCRIPT" "$ISOLATED/"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}' | \"$ISOLATED/intercept-gh-pr-merge.sh\" 2>&1"
  [ "$status" -eq 0 ]
}

# ============================================================
# coverage equalized with the create suite now that
# both entries share lib/intercept-gh-pr-common.sh. Deep shared-flow
# permutations (quoting/heredocs/rewind DAG edge cases) live in
# intercept-gh-pr-create.bats; this set pins the merge wiring and
# per-entry behavior.
# ============================================================

@test "advisory delivery: JSON on stdout carries additionalContext for the model" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}' | LATTICE_HOOK_MODE=advisory '$HOOK_SCRIPT' 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("finish-work")'
  echo "$output" | jq -e '.systemMessage | length > 0'
  echo "$output" | jq -e '.hookSpecificOutput | has("permissionDecision") | not'
}

@test "strict block: advice on stderr, stdout stays empty" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}' | '$HOOK_SCRIPT' 2>/dev/null"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "allows agent-scoped finish-work marker when agent_id present" {
  mkdir -p "$TEST_MARKER_DIR/agent-7"
  touch "$TEST_MARKER_DIR/agent-7/finish-work"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"agent_id\":\"agent-7\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 0 ]
}

@test "blocks when marker exists for a different session" {
  mkdir -p "${ACTIVATED_SKILLS_ROOT}/other-session"
  touch "${ACTIVATED_SKILLS_ROOT}/other-session/finish-work"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
  rm -rf "${ACTIVATED_SKILLS_ROOT}/other-session"
}

@test "blocks gh pr merge in chained command (cd && ...)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"cd /tmp && gh pr merge 4 --squash\"}}"
  [ "$status" -eq 2 ]
}

@test "allows phrase inside heredoc body" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"cat <<DOC\\ngh pr merge 1\\nDOC\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: marker + finish-work load IS an ancestor of the leaf -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/finish-work"
  tf="$(mktemp "${TMPDIR:-/tmp}/merge-transcript.XXXXXX.jsonl")"
  printf '%s\n' \
    '{"uuid":"r1","parentUuid":null,"type":"user"}' \
    '{"uuid":"r2","parentUuid":"r1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"command":"lattice:finish-work"}}]}}' \
    '{"uuid":"r3","parentUuid":"r2","type":"user"}' \
    >"$tf"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 0 ]
  rm -f "$tf"
}

@test "rewind: marker but finish-work load on an ABANDONED branch -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/finish-work"
  tf="$(mktemp "${TMPDIR:-/tmp}/merge-transcript.XXXXXX.jsonl")"
  printf '%s\n' \
    '{"uuid":"s1","parentUuid":null,"type":"user"}' \
    '{"uuid":"s2","parentUuid":"s1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"command":"finish-work"}}]}}' \
    '{"uuid":"s3","parentUuid":"s1","type":"user"}' \
    >"$tf"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
  rm -f "$tf"
}

@test "handles malformed JSON gracefully" {
  run run_hook 'this is not json {'
  [ "$status" -eq 0 ]
}

@test "session dir mtime refreshed even without a marker hit (GC keep-alive)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch -t 202001010000 "$TEST_MARKER_DIR"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
  stale=$(find "$ACTIVATED_SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d -name "$TEST_SESSION" -mtime +1)
  [ -z "$stale" ]
}

@test "intercepts merge through redirections and wrappers" {
  for cmd in ">out.txt gh pr merge 5 --squash" "sudo -u root gh pr merge 5" \
             "<>state gh pr merge 5" ">|state gh pr merge 5" \
             "env -i gh pr merge 5" "timeout 5 gh pr merge 5" "xargs gh pr merge" \
             "chrt 1 gh pr merge 5" "taskset -c 0 gh pr merge 5" \
             "custom-command-runner -- gh pr merge 5"; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"$cmd\"}}"
    [ "$status" -eq 2 ]
  done
}

@test "merge help and prose are not invocations" {
  for cmd in "gh pr merge --help" "echo gh pr merge is the command" "sudo echo gh pr merge"; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"$cmd\"}}"
    [ "$status" -eq 0 ]
  done
}

# ============================================================
# Batch-work merge gate (spc-187 A1, ADR-007 five-piece contract)
# Marker at repo MAIN .lattice/.batch-work-active (single gate point).
# Escape: .batch-merge-authorized flag file with a structured reason.
# ============================================================

@test "batch gate: blocks bare gh pr merge when marker present (strict)" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "batch-work merge gate"
  printf '%s\n' "$output" | grep -qF "night states never reach merged"
  printf '%s\n' "$output" | grep -qF "Legal escape"
  printf '%s\n' "$output" | grep -qF "ADR-007"
}

@test "batch gate: allows gh pr merge when marker absent" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
  # No batch gate trip — the skill-marker check is what blocked (finish-work).
  printf '%s\n' "$output" | grep -qF "finish-work"
  ! printf '%s\n' "$output" | grep -qF "batch-work merge gate"
}

@test "batch gate: honored authorized-merge flag allows merge (strict)" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  printf 'reason: user-authorized: batch done, merge #1 after review\n' \
    >"$LATTICE_BATCH_GATE_HOME/.batch-merge-authorized"
  # finish-work marker present so the skill-marker check also allows
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/finish-work"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1 --squash\"}}"
  [ "$status" -eq 0 ]
}

@test "batch gate: authorized-merge flag empty reason does NOT escape (still blocked)" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  printf '\n  \n' >"$LATTICE_BATCH_GATE_HOME/.batch-merge-authorized"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "batch-work merge gate"
}

@test "batch gate: advisory mode emits JSON additionalContext, allows (exit 0)" {
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}' | LATTICE_HOOK_MODE=advisory '$HOOK_SCRIPT' 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("batch-work merge gate")'
  echo "$output" | jq -e '.systemMessage | contains("batch-work merge gate")'
}

@test "batch gate: does NOT affect gh pr create (verb-scoped)" {
  # Sourcing the create hook entry exercises the same common lib with verb=create;
  # the batch gate must not fire there even with a marker present.
  CREATE_HOOK="$SCRIPT_DIR/hooks/intercept-gh-pr-create.sh"
  [[ -f "$CREATE_HOOK" ]] || skip "create hook entry not present"
  touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}' | LATTICE_HOOK_MODE=strict '$CREATE_HOOK' 2>&1"
  # create hook blocks for its own skill-marker reason, not the batch gate
  ! printf '%s\n' "$output" | grep -qF "batch-work merge gate"
}

@test "batch gate: fails closed when lattice home unresolved + env unset (strict, tkt-239)" {
  # No LATTICE_BATCH_GATE_HOME and not inside a git work tree -> home resolution
  # fails. The gate FAILS CLOSED (strict) so a misresolvable home cannot
  # silently bypass an active marker. Prints the unresolvable-home advisory.
  NOGIT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/no-git-cwd"
  mkdir -p "$NOGIT"
  run bash -c "cd '$NOGIT' && unset LATTICE_BATCH_GATE_HOME && echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}' | LATTICE_HOOK_MODE=strict '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "cannot resolve the lattice home"
  printf '%s\n' "$output" | grep -qF "LATTICE_BATCH_GATE_HOME"
}
