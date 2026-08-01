#!/usr/bin/env bats
# append-adr-index-row.sh — idempotent README index table appender tests.
setup() {
  TMP="$(mktemp -d)"
  SKILL_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  README="$TMP/README.md"
  cat > "$README" <<'EOF'
# Architecture Decision Records (ADR)

## Index

| ADR | Title | Status | Supersede / amend |
| --- | --- | --- | --- |
| [001](./001-foo.md) | Foo | Active | — |
| [002](./002-bar.md) | Bar | Superseded | Superseded by [010](./010-x.md) |

## Other section

text after table
EOF
  touch "$TMP/001-foo.md" "$TMP/002-bar.md"
}

teardown() {
  rm -rf "$TMP"
}

@test "appends a new row at the end of the index table" {
  touch "$TMP/003-baz.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title "Baz" --status "Active"
  [ "$status" -eq 0 ]
  # row appended before the blank line that ends the table
  grep -q '^\| \[003\](./003-baz.md) | Baz | Active | — |' "$README"
  # the "Other section" table/content stays intact
  grep -q '^## Other section' "$README"
  grep -q '^text after table' "$README"
}

@test "idempotent: second run for same num is a no-op" {
  touch "$TMP/003-baz.md"
  bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title "Baz" --status "Active" >/dev/null
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title "Baz" --status "Active"
  [ "$status" -eq 0 ]
  [[ "$(grep -cE '^\| \[003\]' "$README")" -eq 1 ]]
}

@test "existing 001 row is not duplicated" {
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 001 --file "$TMP/001-foo.md" --title "Foo" --status "Active"
  [ "$status" -eq 0 ]
  [[ "$(grep -cE '^\| \[001\]' "$README")" -eq 1 ]]
}

@test "supersede note is placed in the last cell" {
  touch "$TMP/003-baz.md"
  bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title "Baz" --status "Active*" \
    --supersede "Amends [001](./001-foo.md)" >/dev/null
  grep -q '^\| \[003\](./003-baz.md) | Baz | Active\* | Amends \[001\](./001-foo.md) |' "$README"
}

@test "missing README fails closed" {
  touch "$TMP/003-baz.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title "Baz" --status "Active" --readme "$TMP/missing.md"
  [ "$status" -eq 2 ]
}

@test "missing required args fails" {
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" --num 003
  [ "$status" -eq 1 ]
}

@test "title with pipe is rejected (table-cell injection)" {
  touch "$TMP/003-baz.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title "evil | injected" --status "Active" --readme "$README"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be a single index-table cell"* ]]
  # README unchanged
  [[ "$(grep -cE '^\| \[003\]' "$README")" -eq 0 ]]
}

@test "title with backslash is rejected (awk -v escape injection)" {
  touch "$TMP/003-baz.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title 'has\newline' --status "Active" --readme "$README"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be a single index-table cell"* ]]
}

@test "title with newline is rejected (row split)" {
  touch "$TMP/003-baz.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title $'multi\nline' --status "Active" --readme "$README"
  [ "$status" -eq 1 ]
}

@test "non-3-digit --num is rejected" {
  touch "$TMP/003-baz.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num '.*' --file "$TMP/003-baz.md" --title "Baz" --status "Active" --readme "$README"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be exactly 3 digits"* ]]
}

@test "missing ADR file fails closed" {
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-missing.md" --title "Missing" --status "Proposed" --readme "$README"
  [ "$status" -eq 1 ]
  [[ "$(grep -cE '^\| \[003\]' "$README")" -eq 0 ]]
}

@test "unsafe ADR basename is rejected" {
  touch "$TMP/003-bad|cell.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-bad|cell.md" --title "Safe" --status "Proposed" --readme "$README"
  [ "$status" -eq 1 ]
}

@test "file number must match --num" {
  touch "$TMP/004-baz.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/004-baz.md" --title "Baz" --status "Proposed" --readme "$README"
  [ "$status" -eq 1 ]
}

@test "duplicate files for one number fail closed" {
  touch "$TMP/003-alpha.md" "$TMP/003-beta.md"
  run bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-alpha.md" --title "Alpha" --status "Proposed" --readme "$README"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one file"* ]]
}

@test "concurrent distinct appends preserve both rows" {
  touch "$TMP/003-alpha.md" "$TMP/004-beta.md"
  bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-alpha.md" --title "Alpha" --status "Proposed" --readme "$README" >"$TMP/003.out" 2>&1 &
  p1=$!
  bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 004 --file "$TMP/004-beta.md" --title "Beta" --status "Proposed" --readme "$README" >"$TMP/004.out" 2>&1 &
  p2=$!
  wait "$p1"
  wait "$p2"
  [ "$(grep -cE '^\| \[(003|004)\]' "$README")" -eq 2 ]
}

@test "inserts before an immediately following heading" {
  cat > "$README" <<'EOF'
# Architecture Decision Records (ADR)

| ADR | Title | Status | Supersede / amend |
| --- | --- | --- | --- |
| [001](./001-foo.md) | Foo | Active | — |
## Other section
text
EOF
  touch "$TMP/003-baz.md"
  bash "$SKILL_ROOT/scripts/append-adr-index-row.sh" \
    --num 003 --file "$TMP/003-baz.md" --title "Baz" --status "Proposed" --readme "$README"
  row_line=$(grep -n '^| \[003\]' "$README" | cut -d: -f1)
  heading_line=$(grep -n '^## Other section' "$README" | cut -d: -f1)
  [ "$row_line" -lt "$heading_line" ]
}
