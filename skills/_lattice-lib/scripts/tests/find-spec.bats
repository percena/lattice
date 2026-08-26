#!/usr/bin/env bats

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/find-spec.sh"
  TMP_HOME="$(mktemp -d)"
  mkdir -p "$TMP_HOME/specs"
}

teardown() {
  rm -rf "$TMP_HOME"
}

@test "slugged spec resolves by bare N" {
  touch "$TMP_HOME/specs/spc-7-review-chain.md"
  run bash "$SCRIPT" --id 7 --home "$TMP_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TMP_HOME/specs/spc-7-review-chain.md" ]]
}

@test "slugless spec resolves; spc-N id form accepted" {
  touch "$TMP_HOME/specs/spc-12.md"
  run bash "$SCRIPT" --id spc-12 --home "$TMP_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TMP_HOME/specs/spc-12.md" ]]
}

@test "absent spec exits non-zero with a stderr message" {
  run bash "$SCRIPT" --id 3 --home "$TMP_HOME"
  [ "$status" -eq 1 ]
  [[ "$output" == *"spc-3 not found"* ]]
}

@test "exact-N match: spc-4 does not match spc-42" {
  touch "$TMP_HOME/specs/spc-42-night-batch.md"
  run bash "$SCRIPT" --id 4 --home "$TMP_HOME"
  [ "$status" -eq 1 ]
  [[ "$output" == *"spc-4 not found"* ]]

  touch "$TMP_HOME/specs/spc-4-small.md"
  run bash "$SCRIPT" --id 4 --home "$TMP_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TMP_HOME/specs/spc-4-small.md" ]]
}

@test "slugged + slugless for the same N is ambiguous" {
  touch "$TMP_HOME/specs/spc-9-alpha.md" "$TMP_HOME/specs/spc-9.md"
  run bash "$SCRIPT" --id 9 --home "$TMP_HOME"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ambiguous"* ]]
}

@test "malformed id is a usage error (exit 2)" {
  run bash "$SCRIPT" --id 4x --home "$TMP_HOME"
  [ "$status" -eq 2 ]
  [[ "$output" == *"bare decimal"* ]]
}
