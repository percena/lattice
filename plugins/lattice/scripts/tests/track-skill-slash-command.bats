#!/usr/bin/env bats
# Tests for track-skill-slash-command.sh (create-pr + finish-work loads)

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/track-skill-slash-command.sh"
  TEST_SESSION="lattice-slash-test-${BATS_TEST_NUMBER}-$$"
  export ACTIVATED_SKILLS_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/activated-skills"
  mkdir -p "$ACTIVATED_SKILLS_ROOT"
  TEST_MARKER_DIR="${ACTIVATED_SKILLS_ROOT}/${TEST_SESSION}"
  rm -rf "$TEST_MARKER_DIR"
}

teardown() {
  rm -rf "$TEST_MARKER_DIR"
}

run_hook() {
  echo "$1" | "$HOOK_SCRIPT" 2>&1
}

@test "writes finish-work marker for /finish-work prompt" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"/finish-work land it\"}"
  [ "$status" -eq 0 ]
  [ -f "$TEST_MARKER_DIR/finish-work" ]
  [ -f "$TEST_MARKER_DIR/lattice:finish-work" ]
}

@test "writes markers for /lattice:finish-work" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"/lattice:finish-work\"}"
  [ "$status" -eq 0 ]
  [ -f "$TEST_MARKER_DIR/finish-work" ]
  [ -f "$TEST_MARKER_DIR/lattice:finish-work" ]
}

@test "writes create-pr marker for /create-pr prompt" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"/create-pr open it\"}"
  [ "$status" -eq 0 ]
  [ -f "$TEST_MARKER_DIR/create-pr" ]
  [ -f "$TEST_MARKER_DIR/lattice:create-pr" ]
}

@test "writes markers for /lattice:create-pr" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"/lattice:create-pr\"}"
  [ "$status" -eq 0 ]
  [ -f "$TEST_MARKER_DIR/create-pr" ]
  [ -f "$TEST_MARKER_DIR/lattice:create-pr" ]
}

@test "rejects arbitrary /foo:create-pr without authorizing markers" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"/foo:create-pr\"}"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_MARKER_DIR/create-pr" ]
  [ ! -f "$TEST_MARKER_DIR/lattice:create-pr" ]
  [ ! -f "$TEST_MARKER_DIR/foo:create-pr" ]
}

@test "rejects arbitrary /foo:finish-work without authorizing markers" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"/foo:finish-work\"}"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_MARKER_DIR/finish-work" ]
  [ ! -f "$TEST_MARKER_DIR/lattice:finish-work" ]
  [ ! -f "$TEST_MARKER_DIR/foo:finish-work" ]
}

@test "rejects foreign command-name block without authorizing markers" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"<command-name>/foo:create-pr</command-name>\\n<command-message>create-pr</command-message>\"}"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_MARKER_DIR/create-pr" ]
  [ ! -f "$TEST_MARKER_DIR/lattice:create-pr" ]
}

@test "writes marker for synthesized command-name block" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"<command-name>/finish-work</command-name>\\n<command-message>finish-work</command-message>\"}"
  [ "$status" -eq 0 ]
  [ -f "$TEST_MARKER_DIR/finish-work" ]
}

@test "does not write marker for unrelated prompt" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"please finish the work later\"}"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_MARKER_DIR/finish-work" ]
}

@test "does not write marker when finish-work only mentioned mid-sentence" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"I ran finish-work earlier but rewound\"}"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_MARKER_DIR/finish-work" ]
}

@test "scopes marker to agent_id when present" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"agent_id\":\"agent-1\",\"prompt\":\"/finish-work\"}"
  [ "$status" -eq 0 ]
  [ -f "$TEST_MARKER_DIR/agent-1/finish-work" ]
  [ ! -f "$TEST_MARKER_DIR/finish-work" ]
}

@test "missing session_id is a no-op" {
  run run_hook '{"prompt":"/finish-work"}'
  [ "$status" -eq 0 ]
}

@test "fails open (no marker) when activated-skills-root.sh resolver is missing" {
  ISOLATED="${BATS_TEST_TMPDIR:-$(mktemp -d)}/isolated/hooks"
  mkdir -p "$ISOLATED"
  cp "$HOOK_SCRIPT" "$ISOLATED/"
  run bash -c "echo '{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"/finish-work\"}' | \"$ISOLATED/track-skill-slash-command.sh\" 2>&1"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_MARKER_DIR/finish-work" ]
  [ ! -e "/${TEST_SESSION}/finish-work" ]
}

# ============================================================
# anchored command-name scan; no whole-JSON fallback
# ============================================================

@test "no prompt field: /create-pr elsewhere in hook JSON does not mint a marker" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"cwd\":\"/home/u/notes//create-pr\",\"other\":\"<command-name>/create-pr</command-name>\"}"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_MARKER_DIR/create-pr" ]
  [ ! -e "$TEST_MARKER_DIR/lattice:create-pr" ]
}

@test "command-name tag quoted mid-prompt is not an activation" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"the transcript will contain <command-name>/create-pr</command-name> when you use a slash command\"}"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_MARKER_DIR/create-pr" ]
}

@test "synthesized block opening with command-message still counts" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"<command-message>create-pr</command-message><command-name>/create-pr</command-name>\"}"
  [ "$status" -eq 0 ]
  [ -f "$TEST_MARKER_DIR/create-pr" ]
  [ -f "$TEST_MARKER_DIR/lattice:create-pr" ]
}

@test "absurd GC TTL is clamped: fresh sibling survives, stale still GC'd" {
  # Match-all bug: `-mmin +<negative>` on BSD find wipes EVERY sibling,
  # including fresh sessions. Clamp preserves a fresh sibling while still
  # GC'ing an ancient one. Sentinel pre-created so the absurd-TTL call is
  # the ONLY GC (no default-TTL warm-up race).
  printf 'lattice-activated-skills-root-v1 uid=%s\n' "$(id -u)" \
    >"$ACTIVATED_SKILLS_ROOT/.lattice-activated-skills-root"
  chmod 600 "$ACTIVATED_SKILLS_ROOT/.lattice-activated-skills-root"
  fresh="$ACTIVATED_SKILLS_ROOT/fresh-session"
  ancient="$ACTIVATED_SKILLS_ROOT/ancient-session"
  mkdir -p "$fresh" "$ancient"
  touch -t 200001010000 "$ancient"
  printf '{"session_id":"%s","prompt":"/create-pr"}' "$TEST_SESSION" \
    | LATTICE_SKILL_MARKER_TTL_HOURS=99999999999999999999999 bash "$HOOK_SCRIPT"
  for _ in 1 2 3 4 5 6 7 8; do
    [ ! -d "$ancient" ] && break
    sleep 0.1
  done
  [ ! -d "$ancient" ]
  [ -d "$fresh" ]
}

@test "prose mentioning /create-pr mid-prompt does not mint a marker (start-anchored)" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"maybe you should run /create-pr later\"}"
  [ "$status" -eq 0 ]
  [ ! -f "${TEST_MARKER_DIR}/create-pr" ]
  [ ! -f "${TEST_MARKER_DIR}/lattice:create-pr" ]
}

@test "leading whitespace before the slash command still activates" {
  run run_hook "{\"session_id\":\"${TEST_SESSION}\",\"prompt\":\"   /create-pr\"}"
  [ "$status" -eq 0 ]
  [ -f "${TEST_MARKER_DIR}/create-pr" ]
}
