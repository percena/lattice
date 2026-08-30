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
  chmod 000 "$tdir/locked" 2>/dev/null || { chmod 755 "$tdir/locked" 2>/dev/null || true; skip "cannot chmod 000 (running as root?)"; }
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
