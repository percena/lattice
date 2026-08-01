#!/usr/bin/env bats
# Tests for intercept-gh-pr-create.sh PreToolUse hook

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/intercept-gh-pr-create.sh"

  # Unique per-test session id so marker-file tests stay hermetic
  TEST_SESSION="intercept-gh-pr-create-test-${BATS_TEST_NUMBER}-$$"
  export ACTIVATED_SKILLS_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/activated-skills"
  mkdir -p "$ACTIVATED_SKILLS_ROOT"
  TEST_MARKER_DIR="${ACTIVATED_SKILLS_ROOT}/${TEST_SESSION}"
  export LATTICE_HOOK_MODE=strict
}

teardown() {
  rm -rf "$TEST_MARKER_DIR"
}

# Helper: pipe JSON stdin into the hook script, capture exit + output
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

@test "advisory is the product default and allows bare gh pr create with guidance" {
  run run_advisory_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommended path"* ]]
  [[ "$output" == *"Hook mode: advisory"* ]]
}

@test "unknown hook mode degrades to advisory" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}' | LATTICE_HOOK_MODE=unexpected '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hook mode: advisory"* ]]
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
# Strict opt-in — direct invocation is blocked
# ============================================================

@test "blocks bare gh pr create" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"create-pr"* ]]
}

@test "blocks gh pr create with flags (unquoted values)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --title foo --body bar\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"create-pr"* ]]
}

@test "blocks documented repository flag placements around pr create" {
  for command in \
    "gh -R owner/repo pr create" \
    "gh --repo owner/repo pr create" \
    "gh --repo=owner/repo pr create" \
    "gh pr -R owner/repo create" \
    "gh pr --repo owner/repo create"; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"${command}\"}}"
    [ "$status" -eq 2 ]
  done
}

@test "blocks gh pr create with stderr redirect" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create 2>&1\"}}"
  [ "$status" -eq 2 ]
}

@test "blocks gh pr create in backtick command substitution" {
  # Legacy `...` substitution is still a real invocation; the normalizer does
  # not strip backtick spans, so the classifier must treat backtick as a boundary.
  for command in \
    'echo `gh pr create`' \
    'x=`gh pr create`'; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"${command}\"}}"
    [ "$status" -eq 2 ]
  done
}

@test "blocks backtick create substitution inside double quotes" {
  command='x="`gh pr create`"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 2 ]
}

@test "blocks \$(gh pr create) substitution inside double quotes" {
  # $(...) executes inside double quotes; the normalizer must surface it rather
  # than collapsing the whole quoted span to a placeholder.
  command='echo "see: $(gh pr create) done"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 2 ]
}

@test "blocks create after a quoted opening paren inside \$(...)" {
  command='echo "$(printf "("; gh pr create)"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 2 ]
}

@test "allows create text after a quoted closing paren inside \$(...)" {
  command='echo "$(printf ")") gh pr create "'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 0 ]
}

@test "blocks create after case, parameter, comment, and heredoc parens inside \$(...)" {
  commands=(
    'echo "$(case x in x) gh pr create;; esac)"'
    'echo "$(echo ${x:-)}; gh pr create)"'
    $'echo "$(\n# )\ngh pr create\n)"'
    $'echo "$(cat <<\'EOF\'\n)\nEOF\ngh pr create\n)"'
  )
  for command in "${commands[@]}"; do
    run run_hook "$(payload_for_command "$command")"
    [ "$status" -eq 2 ]
  done
}

@test "allows escaped \$(...) that only prints gh pr create text" {
  command='echo "\$(gh pr create)"'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 0 ]
}

@test "allows escaped backticks that only print gh pr create text" {
  command='echo \`gh pr create\`'
  run run_hook "$(payload_for_command "$command")"
  [ "$status" -eq 0 ]
}

@test "blocks gh pr create in chained command (cd && ...)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"cd /tmp && gh pr create\"}}"
  [ "$status" -eq 2 ]
}

@test "blocks gh pr create in chained command (; )" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"cd /tmp ; gh pr create || true\"}}"
  [ "$status" -eq 2 ]
}

@test "blocks gh pr create with title passed via quoted flag (flag is quoted, command is not)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --title 'My PR'\"}}"
  [ "$status" -eq 2 ]
}

# ============================================================
# False positives — phrase inside a quoted value or heredoc is allowed
# ============================================================

@test "allows phrase inside single-quoted flag value" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"git commit -m 'note about gh pr create behaviour'\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase inside double-quoted flag value" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"curl -d \\\"note about gh pr create behaviour\\\" https://example.com\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase inside echoed double-quoted string" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo \\\"gh pr create\\\"\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase inside echoed single-quoted string" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo 'gh pr create'\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase inside plain heredoc body (cat <<EOF ... EOF)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"cat <<EOF\\ngh pr create\\nEOF\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase inside dash-indented heredoc body (<<-EOF)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"cat <<-EOF\\n\\tgh pr create\\n\\tEOF\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase inside quoted-delimiter heredoc (<<'EOF')" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"cat <<'EOF'\\ngh pr create\\nEOF\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase with escaped inner double quotes" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo \\\"he said \\\\\\\"gh pr create\\\\\\\" earlier\\\"\"}}"
  [ "$status" -eq 0 ]
}

# ============================================================
# Help variants — a docs lookup opens no PR, so it is not intercepted
# ============================================================

@test "allows gh pr create --help (reading docs opens no PR)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --help\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh pr create -h but still intercepts a real create after it" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create -h\"}}"
  [ "$status" -eq 0 ]

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --help; gh pr create --title x\"}}"
  [ "$status" -eq 2 ]
}

# ============================================================
# Command position — a word that merely spells "gh" is not an invocation
# ============================================================

@test "allows prose mentioning the command unquoted (not in command position)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo gh pr create is the command\"}}"
  [ "$status" -eq 0 ]

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"grep -rn gh pr create docs/\"}}"
  [ "$status" -eq 0 ]
}

@test "still intercepts a real invocation on a later line of a script" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"git add -A\\ngh pr create --title x\"}}"
  [ "$status" -eq 2 ]
}

@test "still intercepts behind env assignments and a line continuation" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"GH_TOKEN=x gh pr create --title x\"}}"
  [ "$status" -eq 2 ]

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr \\\\\\ncreate --title x\"}}"
  [ "$status" -eq 2 ]
}

# ============================================================
# Skill marker bypass — preserved behavior
# ============================================================

@test "allows gh pr create when session-scoped create-pr marker exists" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh pr create when session-scoped lattice:create-pr marker exists" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/lattice:create-pr"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "allows gh pr create when agent-scoped marker exists and agent_id is present" {
  agent_id="agent-xyz"
  mkdir -p "$TEST_MARKER_DIR/$agent_id"
  touch "$TEST_MARKER_DIR/$agent_id/create-pr"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"agent_id\":\"${agent_id}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "blocks gh pr create when no marker exists for this session" {
  # Ensure the session marker dir definitely doesn't exist
  rm -rf "$TEST_MARKER_DIR"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
}

@test "blocks when marker exists for a different session" {
  other_session="intercept-gh-pr-create-other-session-$$"
  mkdir -p "${ACTIVATED_SKILLS_ROOT}/${other_session}"
  touch "${ACTIVATED_SKILLS_ROOT}/${other_session}/create-pr"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]

  rm -rf "${ACTIVATED_SKILLS_ROOT}/${other_session}"
}

# ============================================================
# Edge cases
# ============================================================

@test "allows empty command" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"\"}}"
  [ "$status" -eq 0 ]
}

@test "handles malformed JSON gracefully" {
  run run_hook 'not valid json'
  [ "$status" -eq 0 ]
}

@test "handles missing tool_input" {
  run run_hook '{"tool_name":"Bash"}'
  [ "$status" -eq 0 ]
}

@test "blocks even when real invocation is preceded by a quoted mention" {
  # A quoted mention shouldn't shield a real invocation that follows
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo 'about to run gh pr create'; gh pr create\"}}"
  [ "$status" -eq 2 ]
}

# ============================================================
# /rewind re-validation — a marker left behind by a rewind must
# not keep the guard satisfied once create-pr is off the active
# transcript branch. /rewind fires no hook, so the intercept
# re-validates the marker against the transcript DAG.
# ============================================================

# Writes a transcript fixture and echoes its path. Each line is one JSONL event.
make_transcript() {
  local tf
  tf="$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/transcript.XXXXXX.jsonl")"
  printf '%s\n' "$@" > "$tf"
  echo "$tf"
}

@test "rewind: marker + create-pr load IS an ancestor of the leaf -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"a1","parentUuid":null,"type":"user"}' \
    '{"uuid":"a2","parentUuid":"a1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"command":"lattice:create-pr"}}]}}' \
    '{"uuid":"a3","parentUuid":"a2","type":"user"}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: marker but create-pr load is on an ABANDONED branch -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # b2 (the create-pr load) branches off b1; the user then rewound to b1 and
  # continued with b3. b3 is the active leaf; b2 is not its ancestor.
  tf="$(make_transcript \
    '{"uuid":"b1","parentUuid":null,"type":"user"}' \
    '{"uuid":"b2","parentUuid":"b1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"command":"create-pr"}}]}}' \
    '{"uuid":"b3","parentUuid":"b1","type":"user"}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"create-pr"* ]]
}

@test "rewind: marker but transcript has no create-pr load at all -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"c1","parentUuid":null,"type":"user"}' \
    '{"uuid":"c2","parentUuid":"c1","type":"user"}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
}

@test "rewind: marker + transcript_path points to a missing file -> fail open (allow)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"/tmp/does-not-exist-$$.jsonl\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: marker + unparseable transcript -> fail open (allow)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript 'not json at all' '{also bad')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

# ---- slash-command activations (marker written by track-skill-slash-command.sh) ----

@test "rewind: marker + /create-pr slash activation IS an ancestor -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"s1","parentUuid":null,"type":"user","message":{"role":"user","content":"/create-pr open the PR"}}' \
    '{"uuid":"s2","parentUuid":"s1","type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: marker + plugin-qualified /lattice:create-pr slash activation -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"q1","parentUuid":null,"type":"user","message":{"role":"user","content":"/lattice:create-pr"}}' \
    '{"uuid":"q2","parentUuid":"q1","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: marker + foreign /foo:create-pr slash is not Lattice activation -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"f1","parentUuid":null,"type":"user","message":{"role":"user","content":"/foo:create-pr"}}' \
    '{"uuid":"f2","parentUuid":"f1","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
}

@test "rewind: marker + foreign Skill(foo:create-pr) is not Lattice activation -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"k1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"uuid":"k2","parentUuid":"k1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"foo:create-pr"}}]}}' \
    '{"uuid":"k3","parentUuid":"k2","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
}

@test "rewind: slash activation on an ABANDONED branch -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"x1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"uuid":"x2","parentUuid":"x1","type":"user","message":{"role":"user","content":"/create-pr"}}' \
    '{"uuid":"x3","parentUuid":"x1","type":"user","message":{"role":"user","content":"use the gh cli"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
}

# ---- fail-open hardening: ambiguity must never re-block ----

@test "rewind: partial parse failure + load absent from branch -> fail open (allow)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # A malformed line means the transcript is not fully parseable; absence is no
  # longer trustworthy, so the helper must stay undetermined (allow).
  tf="$(make_transcript \
    '{"uuid":"p1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{ this line is broken' \
    '{"uuid":"p2","parentUuid":"p1","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: dangling parent chain (incomplete transcript) -> fail open (allow)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # d2's parent (d1) was never written to this slice; the chain is incomplete.
  tf="$(make_transcript \
    '{"uuid":"d2","parentUuid":"d1","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: wrong-shaped Skill input does not crash; valid load still found -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # w2 has a non-dict "input" (must be ignored, not crash); w3 is a valid load.
  tf="$(make_transcript \
    '{"uuid":"w1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"uuid":"w2","parentUuid":"w1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":"not-a-dict"}]}}' \
    '{"uuid":"w3","parentUuid":"w2","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"lattice:create-pr"}}]}}' \
    '{"uuid":"w4","parentUuid":"w3","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: non-UTF-8 bytes in transcript do not crash; valid load found -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(mktemp "${BATS_TEST_TMPDIR:-/tmp}/transcript.XXXXXX.jsonl")"
  printf '{"uuid":"u1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}\n' > "$tf"
  printf '\xff\xfe invalid utf8 bytes here\n' >> "$tf"
  printf '{"uuid":"u2","parentUuid":"u1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"create-pr"}}]}}\n' >> "$tf"
  printf '{"uuid":"u3","parentUuid":"u2","type":"user","message":{"role":"user","content":"go"}}\n' >> "$tf"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

# ---- leaf selection must anchor on a conversation message, not a trailing record ----

@test "rewind: trailing system/attachment record does not become the leaf -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # create-pr is loaded on the active branch (t1->t2->t3). t9 is a trailing
  # system record (has a uuid, parentUuid null) — it must NOT anchor the walk.
  tf="$(make_transcript \
    '{"uuid":"t1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"uuid":"t2","parentUuid":"t1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"create-pr"}}]}}' \
    '{"uuid":"t3","parentUuid":"t2","type":"user","message":{"role":"user","content":"go"}}' \
    '{"uuid":"t9","parentUuid":null,"type":"system","content":"post-turn system note"}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

# ---- slash-command synthesized form vs spoofed mention ----

@test "rewind: genuine synthesized <command-name> command block -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  tf="$(make_transcript \
    '{"uuid":"g1","parentUuid":null,"type":"user","message":{"role":"user","content":"<command-name>/create-pr</command-name>\n<command-message>create-pr</command-message>\n<command-args></command-args>"}}' \
    '{"uuid":"g2","parentUuid":"g1","type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: command-name tag merely quoted mid-message is NOT an activation -> block" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # No genuine load on the active branch; a later message just quotes the tag.
  tf="$(make_transcript \
    '{"uuid":"z1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"uuid":"z2","parentUuid":"z1","type":"user","message":{"role":"user","content":"earlier I ran <command-name>/create-pr</command-name> but rewound"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
}

@test "rewind: cyclic parent chain -> fail open (allow)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # c1 <-> c2 form a parent loop; no create-pr load. A cycle is malformed, so
  # the result must be undetermined rather than a confident "absent" block.
  tf="$(make_transcript \
    '{"uuid":"c1","parentUuid":"c2","type":"user","message":{"role":"user","content":"a"}}' \
    '{"uuid":"c2","parentUuid":"c1","type":"user","message":{"role":"user","content":"b"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: trailing isVisibleInTranscriptOnly node does not become the leaf -> allow" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # create-pr is active on v1->v2->v3; v9 is a transcript-only node appended
  # after, with a null parent — it must not anchor the walk.
  tf="$(make_transcript \
    '{"uuid":"v1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"uuid":"v2","parentUuid":"v1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"create-pr"}}]}}' \
    '{"uuid":"v3","parentUuid":"v2","type":"user","message":{"role":"user","content":"go"}}' \
    '{"uuid":"v9","parentUuid":null,"type":"user","isVisibleInTranscriptOnly":true,"message":{"role":"user","content":"transcript-only note"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: uuid-less conversation record makes result undetermined -> fail open (allow)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  # No create-pr load on the branch, but a user record is missing its uuid —
  # the DAG is incomplete, so the helper must stay undetermined (allow).
  tf="$(make_transcript \
    '{"uuid":"m1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"parentUuid":"m1","type":"user","message":{"role":"user","content":"no uuid here"}}' \
    '{"uuid":"m2","parentUuid":"m1","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

# ============================================================
# Agent-scoped markers also re-validate against transcript
# (previously only session-scoped re-validated)
# ============================================================

@test "rewind: agent-scoped marker + abandoned create-pr branch -> block" {
  agent_id="agent-rewind"
  mkdir -p "$TEST_MARKER_DIR/$agent_id"
  touch "$TEST_MARKER_DIR/$agent_id/create-pr"
  tf="$(make_transcript \
    '{"uuid":"a1","parentUuid":null,"type":"user"}' \
    '{"uuid":"a2","parentUuid":"a1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"command":"create-pr"}}]}}' \
    '{"uuid":"a3","parentUuid":"a1","type":"user"}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"agent_id\":\"${agent_id}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 2 ]
}

@test "rewind: agent-scoped marker + create-pr still ancestor -> allow" {
  agent_id="agent-ok"
  mkdir -p "$TEST_MARKER_DIR/$agent_id"
  touch "$TEST_MARKER_DIR/$agent_id/create-pr"
  tf="$(make_transcript \
    '{"uuid":"b1","parentUuid":null,"type":"user"}' \
    '{"uuid":"b2","parentUuid":"b1","type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"lattice:create-pr"}}]}}' \
    '{"uuid":"b3","parentUuid":"b2","type":"user"}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"agent_id\":\"${agent_id}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

@test "rewind: agent-scoped marker + sidechain-only activation -> allow" {
  # A subagent's Skill activation is a sidechain entry. The scanner cannot
  # anchor sidechain loads on the main-branch walk, so it must stay
  # undetermined (fail open) instead of judging "positively absent" and
  # re-blocking an authorized subagent.
  agent_id="agent-sidechain"
  mkdir -p "$TEST_MARKER_DIR/$agent_id"
  touch "$TEST_MARKER_DIR/$agent_id/create-pr"
  tf="$(make_transcript \
    '{"uuid":"s1","parentUuid":null,"type":"user","message":{"role":"user","content":"hi"}}' \
    '{"uuid":"s2","parentUuid":"s1","type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"lattice:create-pr"}}]}}' \
    '{"uuid":"s3","parentUuid":"s1","type":"user","message":{"role":"user","content":"go"}}')"

  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"agent_id\":\"${agent_id}\",\"transcript_path\":\"${tf}\",\"tool_input\":{\"command\":\"gh pr create --title foo\"}}"
  [ "$status" -eq 0 ]
}

# ============================================================
# Strip-helper failure fails OPEN
# ============================================================

@test "broken python3 fails open instead of matching the raw command" {
  tmp=$(mktemp -d)
  printf '#!/usr/bin/env bash\nexit 1\n' >"$tmp/python3"
  chmod +x "$tmp/python3"
  PATH="$tmp:$PATH" run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo \\\"gh pr create\\\"\"}}"
  rm -rf "$tmp"
  [ "$status" -eq 0 ]
}

# ============================================================
# Normalizer-driven matching: quoted tokens and continuations
# are real invocations; placeholder splices are not
# ============================================================

@test "blocks gh pr create split by line continuation" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr \\\\\\n  create --fill\"}}"
  [ "$status" -eq 2 ]
}

@test "blocks gh \\\"pr\\\" create (quoted token still executes)" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh \\\"pr\\\" create\"}}"
  [ "$status" -eq 2 ]
}

@test "allows quoted fragments that only splice into the phrase" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"echo gh \\\"1\\\" pr \\\"2\\\" create\"}}"
  [ "$status" -eq 0 ]
}

@test "allows phrase that only appears inside a trailing comment" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"git push  # then gh pr create\"}}"
  [ "$status" -eq 0 ]
}

@test "allows when marker present and refreshes session dir mtime" {
  mkdir -p "$TEST_MARKER_DIR"
  touch "$TEST_MARKER_DIR/create-pr"
  touch -t 202001010000 "$TEST_MARKER_DIR"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}"
  [ "$status" -eq 0 ]
  # dir must no longer match -mtime +1 style staleness (modified recently)
  stale=$(find "$ACTIVATED_SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d -name "$TEST_SESSION" -mtime +1)
  [ -z "$stale" ]
}

@test "fails open (allows) when activated-skills-root.sh resolver is missing" {
  ISOLATED="${BATS_TEST_TMPDIR:-$(mktemp -d)}/isolated/hooks"
  mkdir -p "$ISOLATED"
  cp "$HOOK_SCRIPT" "$ISOLATED/"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create --fill\"}}' | \"$ISOLATED/intercept-gh-pr-create.sh\" 2>&1"
  [ "$status" -eq 0 ]
}

# ============================================================
# advisory hook-JSON delivery, pre-filter,
# GC keep-alive (shared lib/intercept-gh-pr-common.sh)
# ============================================================

@test "advisory delivery: JSON on stdout carries additionalContext for the model" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}' | LATTICE_HOOK_MODE=advisory '$HOOK_SCRIPT' 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("create-pr")'
  echo "$output" | jq -e '.systemMessage | length > 0'
  # Never emit a permissionDecision: "allow" would skip the user's permission
  # prompt; the hook is advisory-only.
  echo "$output" | jq -e '.hookSpecificOutput | has("permissionDecision") | not'
}

@test "advisory guidance is not stderr-only (stderr on exit 0 is discarded)" {
  err=$(echo "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}" | LATTICE_HOOK_MODE=advisory "$HOOK_SCRIPT" 2>&1 >/dev/null)
  [ -z "$err" ]
}

@test "strict block: advice on stderr, stdout stays empty" {
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}' | '$HOOK_SCRIPT' 2>/dev/null"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "pre-filter: non-gh command never spawns jq; gh command does" {
  PREFILTER_TMP="$(mktemp -d "${TMPDIR:-/tmp}/prefilter.XXXXXX")"
  JQLOG="$PREFILTER_TMP/jq.log"
  mkdir -p "$PREFILTER_TMP/bin"
  cat >"$PREFILTER_TMP/bin/jq" <<STUB
#!/usr/bin/env bash
echo called >>"$JQLOG"
exec /usr/bin/jq "\$@"
STUB
  chmod +x "$PREFILTER_TMP/bin/jq"
  # Session id must not contain "gh" — the pre-filter scans the raw JSON
  # bytes. The shortcut applies in advisory mode only: strict always takes
  # the full path so \u-escaped payloads cannot slip the guard.
  NOGH_SESSION="prefilter-test-${BATS_TEST_NUMBER}-$$"
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${NOGH_SESSION}\",\"tool_input\":{\"command\":\"ls -la\"}}' | LATTICE_HOOK_MODE=advisory PATH='$PREFILTER_TMP/bin':\$PATH '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
  [ ! -e "$JQLOG" ]
  run bash -c "echo '{\"tool_name\":\"Bash\",\"session_id\":\"${NOGH_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}' | PATH='$PREFILTER_TMP/bin':\$PATH '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 2 ]
  [ -s "$JQLOG" ]
  rm -rf "$PREFILTER_TMP"
}

@test "strict mode skips the pre-filter: unicode-escaped gh cannot slip past" {
  # {"command":"gh pr create"} has no literal "gh" bytes, but jq decodes
  # it to `gh pr create`. Strict mode must take the full path and block.
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"g\\u0068 pr create\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"create-pr"* ]]
}

@test "session dir mtime refreshed even without a marker hit (GC keep-alive)" {
  mkdir -p "$TEST_MARKER_DIR"
  touch -t 202001010000 "$TEST_MARKER_DIR"
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"gh pr create\"}}"
  [ "$status" -eq 2 ]
  stale=$(find "$ACTIVATED_SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d -name "$TEST_SESSION" -mtime +1)
  [ -z "$stale" ]
}

@test "intercepts through leading redirections" {
  for cmd in ">out.txt gh pr create --title x" "2>/dev/null gh pr create --title x" \
             "<>state gh pr create --title x" "3<>state gh pr create --title x" \
             ">|state gh pr create --title x" "2>|state gh pr create --title x" \
             "<<<input gh pr create --title x" "3>&1 gh pr create --title x"; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"$cmd\"}}"
    [ "$status" -eq 2 ]
  done
}

@test "intercepts through wrapper commands with their own options" {
  for cmd in "sudo -u root gh pr create" "env -i gh pr create" "command -p gh pr create" \
             "/usr/bin/env gh pr create" "timeout 5 gh pr create" "nice -n 5 gh pr create" \
             "xargs gh pr create" "nohup gh pr create" "stdbuf -o0 gh pr create" \
             "chrt 1 gh pr create" "taskset -c 0 gh pr create" \
             "env env env env env env env env env gh pr create" \
             "custom-command-runner -- gh pr create"; do
    run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"$cmd\"}}"
    [ "$status" -eq 2 ]
  done
}

@test "a wrapper running a text command is still not an invocation" {
  run run_hook "{\"tool_name\":\"Bash\",\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"command\":\"sudo echo gh pr create\"}}"
  [ "$status" -eq 0 ]
}
