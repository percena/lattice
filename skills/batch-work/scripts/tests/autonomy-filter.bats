#!/usr/bin/env bats
# autonomy-filter.py — scripted step behind batch-work --min-autonomy
# (spc-433 A2 / tkt-461 A10).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export AF="$REPO_ROOT/skills/batch-work/scripts/autonomy-filter.py"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/af.XXXXXX")"
  HOME_L="$TEST_DIR/.lattice"
  mkdir -p "$HOME_L/tickets"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# binder <tkt-N> <slug> [<autonomy-cell>|none]
binder() {
  local d="$HOME_L/tickets/$1-$2"; mkdir -p "$d"
  {
    printf '# %s-%s\n\n| Field | Value |\n| --- | --- |\n| status | queued |\n' "$1" "$2"
    if [ "${3:-none}" != none ]; then printf '| autonomy | %s |\n' "$3"; fi
    printf '\n## Notes\n\n| autonomy | 4 |\n'   # later example table must NOT shadow the card
  } >"$d/README.md"
}

@test "tkt-461 A10: threshold partitions selected vs skipped with the never-spawned reason" {
  binder tkt-1 a 4; binder tkt-2 b 3; binder tkt-3 c 1; binder tkt-4 d 0
  run python3 "$AF" --min-autonomy 3 --home "$HOME_L" tkt-1 tkt-2 tkt-3 tkt-4
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["selected"]==["tkt-1","tkt-2"], d
assert [s["id"] for s in d["skipped"]]==["tkt-3","tkt-4"], d
assert all(s["reason"]=="autonomy-below-threshold" for s in d["skipped"]), d
assert d["skipped"][0]["autonomy"]==1 and d["skipped"][0]["source"]=="row", d'
}

@test "tkt-461 A10: a binder without an autonomy row scores 2 (rubric default) and is filtered at the default threshold 3" {
  binder tkt-5 legacy none
  run python3 "$AF" --min-autonomy 3 --home "$HOME_L" tkt-5
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"autonomy": 2'
  printf '%s\n' "$output" | grep -qF '"source": "default"'
  run python3 "$AF" --min-autonomy 2 --home "$HOME_L" tkt-5
  printf '%s\n' "$output" | grep -qF '"selected": ['
  printf '%s\n' "$output" | python3 -c 'import json,sys; assert json.load(sys.stdin)["selected"]==["tkt-5"]'
}

@test "tkt-461 A10: --min-autonomy 0 disables the filter (everything selected, still exit 0)" {
  binder tkt-6 z 0; binder tkt-7 y none
  run python3 "$AF" --min-autonomy 0 --home "$HOME_L" tkt-6 tkt-7
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["selected"]==["tkt-6","tkt-7"] and d["skipped"]==[], d'
}

@test "tkt-461 A10: --all scans every binder; missing binders are reported, not fatal; bare numeric ids accepted" {
  binder tkt-8 p 4; binder tkt-9 q 2
  run python3 "$AF" --min-autonomy 3 --home "$HOME_L" --all 42
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["selected"]==["tkt-8"] and d["skipped"][0]["id"]=="tkt-9" and d["missing_binder"]==["tkt-42"], d'
}

@test "tkt-461 A10: usage errors exit 2 (out-of-range threshold, no ids)" {
  run python3 "$AF" --min-autonomy 9 --home "$HOME_L" tkt-1
  [ "$status" -eq 2 ]
  run python3 "$AF" --min-autonomy 3 --home "$HOME_L"
  [ "$status" -eq 2 ]
}

@test "tkt-480 A2: capital-A autonomy row is scored (not missed as default 2)" {
  # Regression: AUTONOMY_ROW_RE lacked re.I, so `| Autonomy | 4 |` was missed
  # and scored default 2 → skipped under --min-autonomy 3 even though it's a 4.
  # The validator (validate-lattice-artifacts.py AUTONOMY_TABLE_RE) has re.I, so
  # the two consumers disagreed. Now both are case-insensitive.
  local d="$HOME_L/tickets/tkt-1-cap"; mkdir -p "$d"
  {
    printf '# tkt-1-cap\n\n| Field | Value |\n| --- | --- |\n| status | queued |\n| Autonomy | 4 |\n'
    printf '\n## Notes\n\n| autonomy | 4 |\n'
  } >"$d/README.md"
  run python3 "$AF" --min-autonomy 3 --home "$HOME_L" tkt-1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["selected"]==["tkt-1"], d   # capital-A row scored 4 → selected, not skipped-as-default-2'
}
