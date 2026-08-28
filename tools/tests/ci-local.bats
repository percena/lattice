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
  [[ "$output" != *'!/usr/bin/env'* ]]
  [[ "$output" == *'Usage: bash tools/ci-local.sh'* ]]
}

@test "ci-local --help documents --release-check and --fast without truncation" {
  run bash "$CI_LOCAL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'--release-check'* ]]
  [[ "$output" == *'dev-mode (lenient: only non-decrease enforced). [ADR-005]'* ]]
  [[ "$output" == *'--fast           skip the bats suites'* ]]
  # last line must be a complete sentence (the old sed cap cut mid-sentence)
  [[ "$(tail -n 1 <<< "$output")" == *'exit code is nonzero if any step failed.'* ]]
}

@test "ci-local rejects unknown arguments with exit 2" {
  run bash "$CI_LOCAL" --definitely-not-a-flag
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown argument'* ]]
}

@test "ci-local --base-ref with an unresolvable ref FAILs plugin-versions (no silent skip)" {
  run bash "$CI_LOCAL" --fast --base-ref bogus-ref-tkt159
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not resolve to a commit"* ]]
  [[ "$output" != *'skip   no bundled paths changed vs bogus-ref-tkt159'* ]]
}

@test "ci-local --base-ref with a valid ref does not trip the fail-loud guard" {
  run bash "$CI_LOCAL" --fast --base-ref HEAD
  [ "$status" -eq 0 ]
  [[ "$output" != *'does not resolve to a commit'* ]]
}
