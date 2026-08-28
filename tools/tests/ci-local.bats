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
