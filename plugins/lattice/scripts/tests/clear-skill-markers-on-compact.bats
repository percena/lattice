#!/usr/bin/env bats
# Tests for clear-skill-markers-on-compact.sh (PreCompact).
# Hook is byte-identical across plugins (shared-file-drift.bats); suite lives
# on lattice and covers the shared contract.

setup_file() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HOOK="$PLUGIN_ROOT/hooks/clear-skill-markers-on-compact.sh"
}

setup() {
  SESSION="bats-clear-$$-${BATS_TEST_NUMBER}"
  export ACTIVATED_SKILLS_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/activated-skills"
  MARKER_ROOT="$ACTIVATED_SKILLS_ROOT"
  mkdir -p "$MARKER_ROOT/$SESSION"
  touch "$MARKER_ROOT/$SESSION/create-pr"
}

teardown() {
  rm -rf "${MARKER_ROOT:?}/${SESSION}"
}

@test "clears session markers when resolver is present" {
  printf '{"session_id":"%s"}' "$SESSION" | bash "$HOOK"
  [ ! -d "$MARKER_ROOT/$SESSION" ]
}

@test "fails open (exit 0, markers untouched) when activated-skills-root.sh resolver is missing" {
  ISOLATED="${BATS_TEST_TMPDIR:-$(mktemp -d)}/isolated/hooks"
  mkdir -p "$ISOLATED"
  cp "$HOOK" "$ISOLATED/"
  run bash -c "printf '{\"session_id\":\"%s\"}' '$SESSION' | bash '$ISOLATED/clear-skill-markers-on-compact.sh'"
  [ "$status" -eq 0 ]
  # Without a resolver the hook must not invent paths or wipe markers elsewhere.
  [ -f "$MARKER_ROOT/$SESSION/create-pr" ]
}

# ============================================================
# rm -rf honours the same symlink/ownership checks
# the writers enforce
# ============================================================

@test "symlinked session dir is not recursively deleted through" {
  GUARD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/compact-guard.XXXXXX")"
  mkdir -p "$GUARD_TMP/precious"
  touch "$GUARD_TMP/precious/keep"
  ln -s "$GUARD_TMP/precious" "$MARKER_ROOT/$SESSION"
  run bash -c "echo '{\"session_id\":\"${SESSION}\"}' | '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
  [ -f "$GUARD_TMP/precious/keep" ]
  rm -f "$MARKER_ROOT/$SESSION"
  rm -rf "$GUARD_TMP"
}

@test "symlinked root is not deleted through" {
  GUARD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/compact-guard.XXXXXX")"
  mkdir -p "$GUARD_TMP/real-root/$SESSION"
  touch "$GUARD_TMP/real-root/$SESSION/create-pr"
  ln -s "$GUARD_TMP/real-root" "$GUARD_TMP/link-root"
  run bash -c "echo '{\"session_id\":\"${SESSION}\"}' | ACTIVATED_SKILLS_ROOT='$GUARD_TMP/link-root' '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
  [ -f "$GUARD_TMP/real-root/$SESSION/create-pr" ]
  rm -rf "$GUARD_TMP"
}
