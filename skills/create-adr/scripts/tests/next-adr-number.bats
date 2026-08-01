#!/usr/bin/env bats
# next-adr-number.sh — pure-read 3-digit max+1 allocator tests.
setup() {
  ADR_HOME_TMP="$(mktemp -d)"
  SKILL_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

teardown() {
  rm -rf "$ADR_HOME_TMP"
}

@test "empty folder returns 001" {
  run bash "$SKILL_ROOT/scripts/next-adr-number.sh" --home "$ADR_HOME_TMP"
  [ "$status" -eq 0 ]
  [ "$output" = "001" ]
}

@test "max of a few is max+1 zero-padded 3-digit" {
  touch "$ADR_HOME_TMP/001-foo.md"
  touch "$ADR_HOME_TMP/009-bar.md"
  touch "$ADR_HOME_TMP/010-baz.md"
  run bash "$SKILL_ROOT/scripts/next-adr-number.sh" --home "$ADR_HOME_TMP"
  [ "$status" -eq 0 ]
  [ "$output" = "011" ]
}

@test "ignores template.md and README.md" {
  touch "$ADR_HOME_TMP/template.md"
  touch "$ADR_HOME_TMP/README.md"
  touch "$ADR_HOME_TMP/003-real.md"
  run bash "$SKILL_ROOT/scripts/next-adr-number.sh" --home "$ADR_HOME_TMP"
  [ "$status" -eq 0 ]
  [ "$output" = "004" ]
}

@test "handles gap (non-contiguous) as max+1" {
  touch "$ADR_HOME_TMP/005-a.md"
  touch "$ADR_HOME_TMP/012-b.md"
  run bash "$SKILL_ROOT/scripts/next-adr-number.sh" --home "$ADR_HOME_TMP"
  [ "$status" -eq 0 ]
  [ "$output" = "013" ]
}

@test "missing home fails closed" {
  run bash "$SKILL_ROOT/scripts/next-adr-number.sh" --home "$ADR_HOME_TMP/does-not-exist"
  [ "$status" -eq 1 ]
}

@test "LATTICE_ADR_HOME env is used when --home omitted" {
  touch "$ADR_HOME_TMP/027-x.md"
  export LATTICE_ADR_HOME="$ADR_HOME_TMP"
  run bash "$SKILL_ROOT/scripts/next-adr-number.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "028" ]
}
