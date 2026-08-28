#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  SKILL_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEMPLATE="$TMP/template.md"
  printf '%s\n' '# ADR NNN: Title' > "$TEMPLATE"
}

teardown() {
  rm -rf "$TMP"
}

@test "claims a template file without overwriting" {
  run bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 001 --slug storage-layout --template "$TEMPLATE" --home "$TMP"
  [ "$status" -eq 0 ]
  expected="$(cd -P "$TMP" && pwd)/001-storage-layout.md"
  [ "$output" = "$expected" ]
  grep -q '^# ADR NNN: Title' "$output"
}

@test "same number with a different slug fails closed" {
  bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 001 --slug alpha --template "$TEMPLATE" --home "$TMP" >/dev/null
  run bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 001 --slug beta --template "$TEMPLATE" --home "$TMP"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "expected 002"
  [ ! -e "$TMP/001-beta.md" ]
}

@test "claim must still be the current max plus one" {
  run bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 002 --slug skipped --template "$TEMPLATE" --home "$TMP"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "expected 001"
  [ ! -e "$TMP/002-skipped.md" ]
}

@test "pre-existing duplicate number blocks new claims" {
  touch "$TMP/001-alpha.md" "$TMP/001-beta.md"
  run bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 002 --slug gamma --template "$TEMPLATE" --home "$TMP"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "multiple files"
}

@test "concurrent claims for one number produce exactly one file" {
  bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 001 --slug alpha --template "$TEMPLATE" --home "$TMP" >"$TMP/alpha.out" 2>&1 &
  p1=$!
  bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 001 --slug beta --template "$TEMPLATE" --home "$TMP" >"$TMP/beta.out" 2>&1 &
  p2=$!
  s1=0; wait "$p1" || s1=$?
  s2=0; wait "$p2" || s2=$?
  [ $((s1 + s2)) -eq 1 ]
  [ "$(find "$TMP" -maxdepth 1 -name '001-*.md' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "unsafe slug is rejected" {
  run bash "$SKILL_ROOT/scripts/claim-adr-file.sh" \
    --num 001 --slug 'bad|slug' --template "$TEMPLATE" --home "$TMP"
  [ "$status" -eq 1 ]
}
