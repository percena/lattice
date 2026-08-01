#!/usr/bin/env bats
# Tests for track-skill-activation.sh (PreToolUse:Skill marker writer).

setup_file() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HOOK="$PLUGIN_ROOT/hooks/track-skill-activation.sh"
}

setup() {
  SESSION="bats-track-$$-${BATS_TEST_NUMBER}"
  # Self-managed per-test tmp dir: a shared BATS_TEST_TMPDIR (pre-1.4 bats
  # workaround) must not leak the ownership sentinel between tests.
  TEST_TMP="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/track-skill.XXXXXX")"
  export ACTIVATED_SKILLS_ROOT="$TEST_TMP/activated-skills"
  MARKER_ROOT="$ACTIVATED_SKILLS_ROOT"
  mkdir -p "$MARKER_ROOT"
}

teardown() {
  rm -rf "${TEST_TMP:?}"
}

@test "writes session-scoped marker for skill activation" {
  printf '{"session_id":"%s","tool_name":"Skill","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  [ -f "$MARKER_ROOT/$SESSION/create-pr" ]
  [ -f "$MARKER_ROOT/.lattice-activated-skills-root" ]
}

@test "writes agent-scoped marker when agent_id present" {
  printf '{"session_id":"%s","agent_id":"agent-1","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  [ -f "$MARKER_ROOT/$SESSION/agent-1/create-pr" ]
  [ ! -f "$MARKER_ROOT/$SESSION/create-pr" ]
}

@test "plugin-qualified skill names are allowed" {
  printf '{"session_id":"%s","tool_input":{"skill":"lattice:create-pr"}}' "$SESSION" | bash "$HOOK"
  [ -f "$MARKER_ROOT/$SESSION/lattice:create-pr" ]
}

@test "rejects skill names with path separators" {
  printf '{"session_id":"%s","tool_input":{"skill":"../escape"}}' "$SESSION" | bash "$HOOK"
  [ ! -e "$MARKER_ROOT/../escape" ]
  [ ! -e "$MARKER_ROOT/escape" ]
  [ ! -d "$MARKER_ROOT/$SESSION" ] || [ -z "$(ls -A "$MARKER_ROOT/$SESSION")" ]
}

@test "missing session_id is a silent no-op" {
  run bash -c "printf '{\"tool_input\":{\"skill\":\"create-pr\"}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "session dir mtime is refreshed on every activation (GC survival)" {
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  touch -t 202001010000 "$MARKER_ROOT/$SESSION"
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  # dir must be fresh again (find -mtime +1 must NOT match it)
  stale=$(find "$MARKER_ROOT" -mindepth 1 -maxdepth 1 -type d -name "$SESSION" -mtime +1)
  [ -z "$stale" ]
}

@test "owned sentinel root garbage-collects stale session directories" {
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  mkdir -p "$MARKER_ROOT/stale-session"
  touch -t 202001010000 "$MARKER_ROOT/stale-session"
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  for _ in 1 2 3 4 5; do
    [ ! -d "$MARKER_ROOT/stale-session" ] && break
    sleep 0.1
  done
  [ ! -d "$MARKER_ROOT/stale-session" ]
}

@test "GC TTL is env-tunable and defaults survive a 2-day-old session" {
  # 48h-old dir: survives the default 72h TTL, dies under a 1h TTL.
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  aged="$MARKER_ROOT/aged-session"
  mkdir -p "$aged"
  two_days_ago=$(date -d '2 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-2d +%Y%m%d%H%M)
  touch -t "$two_days_ago" "$aged"

  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  sleep 0.3
  [ -d "$aged" ]

  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" \
    | LATTICE_SKILL_MARKER_TTL_HOURS=1 bash "$HOOK"
  for _ in 1 2 3 4 5; do
    [ ! -d "$aged" ] && break
    sleep 0.1
  done
  [ ! -d "$aged" ]
}

@test "non-numeric GC TTL falls back to the default instead of breaking find" {
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  aged="$MARKER_ROOT/aged-session2"
  mkdir -p "$aged"
  two_days_ago=$(date -d '2 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-2d +%Y%m%d%H%M)
  touch -t "$two_days_ago" "$aged"
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" \
    | LATTICE_SKILL_MARKER_TTL_HOURS=bogus bash "$HOOK"
  sleep 0.3
  [ -d "$aged" ]  # 48h < 72h default -> survives; hook exited cleanly
}

@test "absurd GC TTL is clamped: fresh sibling survives, stale still GC'd" {
  # A 20+ digit TTL passes the `[[ -gt 0 ]]` guard but overflows
  # $((ttl*60)) to a negative -mmin. With BSD find `-mmin +<negative>` is
  # MATCH-ALL (not rejected) -> GC would wipe EVERY sibling, including fresh
  # sessions — a real data-loss path, not fail-safe. Clamp to 100000h
  # (~11.4y): a fresh sibling must survive, an ancient one (>11.4y) still GC'd.
  # Sentinel pre-created so the absurd-TTL call is the ONLY GC (a default-TTL
  # warm-up would race-remove the ancient dir via 72h GC first).
  printf 'lattice-activated-skills-root-v1 uid=%s\n' "$(id -u)" \
    >"$MARKER_ROOT/.lattice-activated-skills-root"
  chmod 600 "$MARKER_ROOT/.lattice-activated-skills-root"
  fresh="$MARKER_ROOT/fresh-session"
  ancient="$MARKER_ROOT/ancient-session"
  mkdir -p "$fresh" "$ancient"
  touch -t 200001010000 "$ancient"  # ~26 years old, well past the 100000h clamp
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" \
    | LATTICE_SKILL_MARKER_TTL_HOURS=99999999999999999999999 bash "$HOOK"
  for _ in 1 2 3 4 5 6 7 8; do
    [ ! -d "$ancient" ] && break
    sleep 0.1
  done
  [ ! -d "$ancient" ]   # GC still runs under the clamp
  [ -d "$fresh" ]       # fresh session must survive (bug would match-all -> wipe)
}

@test "nonempty override without sentinel never recursively cleans unrelated directories" {
  mkdir -p "$MARKER_ROOT/unowned-stale"
  touch -t 202001010000 "$MARKER_ROOT/unowned-stale"
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  sleep 0.2
  [ -f "$MARKER_ROOT/$SESSION/create-pr" ]
  [ -d "$MARKER_ROOT/unowned-stale" ]
  [ ! -e "$MARKER_ROOT/.lattice-activated-skills-root" ]
}

@test "symlink override is rejected without writing or deleting through it" {
  REAL_ROOT="$TEST_TMP/real-root"
  LINK_ROOT="$TEST_TMP/link-root"
  mkdir -p "$REAL_ROOT/keep"
  ln -s "$REAL_ROOT" "$LINK_ROOT"
  export ACTIVATED_SKILLS_ROOT="$LINK_ROOT"
  printf '{"session_id":"%s","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  [ -d "$REAL_ROOT/keep" ]
  [ ! -e "$REAL_ROOT/$SESSION/create-pr" ]
}

@test "invalid agent_id falls back to session-scoped marker" {
  printf '{"session_id":"%s","agent_id":"bad/id","tool_input":{"skill":"create-pr"}}' "$SESSION" | bash "$HOOK"
  [ -f "$MARKER_ROOT/$SESSION/create-pr" ]
  [ ! -d "$MARKER_ROOT/$SESSION/bad" ]
}

@test "fails open (no marker) when activated-skills-root.sh resolver is missing" {
  ISOLATED="$TEST_TMP/isolated/hooks"
  mkdir -p "$ISOLATED"
  cp "$HOOK" "$ISOLATED/"
  # No ../scripts/activated-skills-root.sh beside the isolated hook copy.
  run bash -c "printf '{\"session_id\":\"%s\",\"tool_input\":{\"skill\":\"create-pr\"}}' '$SESSION' | bash '$ISOLATED/track-skill-activation.sh'"
  [ "$status" -eq 0 ]
  # Must not write under ACTIVATED_SKILLS_ROOT or invent a root-relative path.
  [ ! -e "$MARKER_ROOT/$SESSION/create-pr" ]
  [ ! -e "/$SESSION/create-pr" ]
}
