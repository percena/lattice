#!/usr/bin/env bats

# tkt-159: ci-local.sh arg handling, --help integrity, and the fail-loud
# --base-ref contract (a bogus ref must FAIL plugin-versions, never skip it).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CI_LOCAL="$REPO_ROOT/tools/ci-local.sh"
}

@test "ci-local --help exits 0 and does not leak the shebang" {
  run bash "$CI_LOCAL" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'Usage: bash tools/ci-local.sh'
  # negative grep is terminal: `! cmd` only gates a test in last position (#167)
  if printf '%s\n' "$output" | grep -qF '!/usr/bin/env'; then false; fi
}

@test "ci-local --help documents --release-check and --fast without truncation" {
  run bash "$CI_LOCAL" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF -- '--release-check'
  printf '%s\n' "$output" | grep -qF 'dev-mode (lenient: only non-decrease enforced). [ADR-005]'
  printf '%s\n' "$output" | grep -qF -- '--fast           skip the bats suites'
  # last line must be a complete sentence (the old sed cap cut mid-sentence)
  tail -n 1 <<< "$output" | grep -qF 'exit code is nonzero if any step failed.'
}

@test "ci-local rejects unknown arguments with exit 2" {
  run bash "$CI_LOCAL" --definitely-not-a-flag
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF 'unknown argument'
}

@test "ci-local --base-ref with an unresolvable ref FAILs plugin-versions (no silent skip)" {
  run bash "$CI_LOCAL" --fast --base-ref bogus-ref-tkt159
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "does not resolve to a commit"
  [ -z "$(printf '%s\n' "$output" | grep -F 'skip   no bundled paths changed vs bogus-ref-tkt159')" ]
}

@test "ci-local --base-ref with a valid ref does not trip the fail-loud guard" {
  run bash "$CI_LOCAL" --fast --base-ref HEAD
  # Assert only guard-specific behavior: whole-run exit 0 would couple this
  # test to host state (shellcheck presence) and tree dirtiness.
  printf '%s\n' "$output" | grep -qE 'plugin-versions +(pass|skip)'
  if printf '%s\n' "$output" | grep -qF 'does not resolve to a commit'; then false; fi
}

# ===================== tkt-239: step_symlinks find-rc + plugin_validate note =====================

@test "step_symlinks: find failure surfaces as FAIL, not false green (tkt-239)" {
  # Extract the ACTUAL step_symlinks from ci-local.sh and exercise it.
  eval "$(sed -n '/^step_symlinks()/,/^}$/p' "$CI_LOCAL")"
  export -f step_symlinks
  local tdir="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  mkdir -p "$tdir/locked"
  # tkt-462 A14: for uid 0 chmod 000 SUCCEEDS but does not restrict, so the
  # old "chmod failed → skip" guard never fired and the test failed instead.
  if [ "$(id -u)" -eq 0 ]; then skip "chmod 000 is ineffective for root"; fi
  chmod 000 "$tdir/locked" 2>/dev/null || { chmod 755 "$tdir/locked" 2>/dev/null || true; skip "cannot chmod 000"; }
  run bash -c "cd '$tdir' && step_symlinks"
  chmod 755 "$tdir/locked" 2>/dev/null || true
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "find exited non-zero"
}

@test "step_symlinks: clean tree passes (rc capture does not regress the happy path)" {
  eval "$(sed -n '/^step_symlinks()/,/^}$/p' "$CI_LOCAL")"
  export -f step_symlinks
  local tdir="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  run bash -c "cd '$tdir' && step_symlinks"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "step_plugin_validate: prints installed-version note (tkt-239)" {
  eval "$(sed -n '/^step_plugin_validate()/,/^}$/p' "$CI_LOCAL")"
  export -f step_plugin_validate
  local tbin="${BATS_TEST_TMPDIR:-$(mktemp -d)}/bin"
  mkdir -p "$tbin"
  cat >"$tbin/claude" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "1.2.3" ;;
  plugin) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tbin/claude"
  local saved_path="$PATH"
  export PATH="$tbin:$PATH"
  run bash -c "cd '$REPO_ROOT' && step_plugin_validate"
  export PATH="$saved_path"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "note: installed claude (1.2.3) differs from CI pin @2.1.216"
}

# ===================== tkt-261: bats version parity + workflow pin equality (spc-254 A9) =====================

# Both CIs must pin the SAME bats version, and ci-local's BATS_PIN must match.
# Editing one workflow (or ci-local) without the other breaks this parity test.
@test "both workflows pin the same bats version and match ci-local BATS_PIN (spc-254 A9)" {
  local scripts_pin hooks_pin ci_pin
  scripts_pin="$(grep -oE 'v1\.[0-9]+\.[0-9]+' "$REPO_ROOT/.github/workflows/lattice-scripts.yml" | head -n1)"
  hooks_pin="$(grep -oE 'v1\.[0-9]+\.[0-9]+' "$REPO_ROOT/.github/workflows/plugin-hooks.yml" | head -n1)"
  ci_pin="$(sed -n 's/^BATS_PIN="\([0-9.]*\)"/\1/p' "$CI_LOCAL")"
  [ -n "$scripts_pin" ]
  [ -n "$hooks_pin" ]
  [ -n "$ci_pin" ]
  [ "$scripts_pin" = "$hooks_pin" ]
  [ "$scripts_pin" = "v$ci_pin" ]
}

# ci-local must NOT silently use any PATH bats: a version mismatch reports
# DEGRADED (non-fatal but visible), never a silent pass.
@test "ci-local reports DEGRADED on bats version mismatch (never silent) (spc-254 A9)" {
  local tbin="${BATS_TEST_TMPDIR:-$(mktemp -d)}/bin"
  mkdir -p "$tbin"
  # Fake bats that reports a version ci-local's pin does NOT match.
  cat >"$tbin/bats" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Bats 9.9.9-mock" ;;
  *) echo "bats: no suites in --fast" >&2; exit 0 ;;
esac
EOF
  chmod +x "$tbin/bats"
  local saved_path="$PATH"
  export PATH="$tbin:$PATH"
  run bash "$CI_LOCAL" --fast --base-ref HEAD
  export PATH="$saved_path"
  # degraded is non-fatal: exit 0 unless some unrelated host step FAILED.
  printf '%s\n' "$output" | grep -qF 'bats-version-parity'
  printf '%s\n' "$output" | grep -qiE 'DEGRADED'
  printf '%s\n' "$output" | grep -qF '9.9.9-mock'
  printf '%s\n' "$output" | grep -qiE 'may not predict GitHub CI'
}

# A matching bats version must report pass (not degraded), so a regression that
# flips the check the wrong way is caught.
@test "ci-local reports pass when bats matches the CI pin (spc-254 A9)" {
  local ci_pin real_bats_ver
  ci_pin="$(sed -n 's/^BATS_PIN="\([0-9.]*\)"/\1/p' "$CI_LOCAL")"
  real_bats_ver="$(bats --version 2>/dev/null || true)"
  # This test only runs when the host bats actually matches the pin (the
  # common dev case). Skip on hosts with a different bats (CI pins v1.13.0).
  if ! printf '%s' "$real_bats_ver" | grep -qF "$ci_pin"; then
    skip "host bats ($real_bats_ver) != pin v$ci_pin; parity-pass case not exercisable here"
  fi
  run bash "$CI_LOCAL" --fast --base-ref HEAD
  printf '%s\n' "$output" | grep -qE 'bats-version-parity +pass'
  if printf '%s\n' "$output" | grep -qiE 'DEGRADED.*bats'; then false; fi
}

# ===================== tkt-261: installed-skill drift check dev-mode wiring (spc-254 A9) =====================

@test "installed-skill drift check runs in dev mode, skips under --release-check (spc-254 A9)" {
  run bash "$CI_LOCAL" --fast --base-ref HEAD
  printf '%s\n' "$output" | grep -qF 'installed-skill-drift'
  # dev mode (default) runs or skips-with-reason, never silent absence
  run bash "$CI_LOCAL" --fast --release-check --base-ref HEAD
  printf '%s\n' "$output" | grep -qE 'installed-skill-drift +skip'
  printf '%s\n' "$output" | grep -qiE 'dev-mode only'
}

@test "ci-local --help documents bats parity + drift dev-mode behavior (spc-254 A9)" {
  run bash "$CI_LOCAL" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qiE 'Bats version parity'
  printf '%s\n' "$output" | grep -qiE 'BATS_PIN'
  printf '%s\n' "$output" | grep -qiE 'installed-skill drift check runs only in dev mode'
  printf '%s\n' "$output" | grep -qF 'pass/FAIL/skip/degraded'
}

# ===================== tkt-463 A15: bats pin single source + base-baseline parity =====================

@test "tkt-463: BATS_PIN is read from tools/.bats-pin (single source shared with both workflows)" {
  local file_tag script_pin
  file_tag="$(sed -n 's/^tag=v//p' "$REPO_ROOT/tools/.bats-pin")"
  [ -n "$file_tag" ]
  grep -qE '^sha=[0-9a-f]{40}$' "$REPO_ROOT/tools/.bats-pin"
  # extract the resolver + fallback block from ci-local.sh and evaluate it
  script_pin="$(ROOT="$REPO_ROOT" bash -c "$(sed -n '/^BATS_PIN="/,/^fi$/p' "$CI_LOCAL"); printf '%s' \"\$BATS_PIN\"")"
  [ "$script_pin" = "$file_tag" ]
  # both workflows read the same file and verify the sha before install.sh
  grep -qF 'BATS_PIN_FILE: tools/.bats-pin' "$REPO_ROOT/.github/workflows/lattice-scripts.yml"
  grep -qF 'BATS_PIN_FILE: tools/.bats-pin' "$REPO_ROOT/.github/workflows/plugin-hooks.yml"
  grep -qF 'rev-parse HEAD' "$REPO_ROOT/.github/workflows/lattice-scripts.yml"
  grep -qF 'rev-parse HEAD' "$REPO_ROOT/.github/workflows/plugin-hooks.yml"
}

@test "tkt-463: lattice-artifacts step compares against the BASE-ref baseline when one resolves (artifacts.yml parity)" {
  eval "$(sed -n '/^step_artifacts()/,/^}$/p' "$CI_LOCAL")"
  export -f step_artifacts
  run bash -c "cd '$REPO_ROOT' && BASE_REF=HEAD BASE_REF_OK=1 step_artifacts"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'baseline: base-ref HEAD'
  # no base ref → feature-file fallback, still runs the validator
  run bash -c "cd '$REPO_ROOT' && BASE_REF='' BASE_REF_OK=0 step_artifacts"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'baseline: feature file'
}
