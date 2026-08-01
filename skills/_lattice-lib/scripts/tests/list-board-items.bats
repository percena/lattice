#!/usr/bin/env bats
# Tests for list-board-items.sh (stubbed gh; no network).
# Pins gh project item-list --format json shape

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export LIST="$REPO_ROOT/skills/_lattice-lib/scripts/list-board-items.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lbi.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cd "$MAIN"

  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export GH_LOG="$TEST_DIR/gh.log"
  export GH_MODE="ok"
  : >"$GH_LOG"

  # Default fixture: mixed Ready/Done, Issue/PR, epic label
  export GH_JSON
  GH_JSON=$(cat <<'JSON'
{
  "items": [
    {
      "id": "PVTI_a",
      "status": "Ready",
      "labels": ["feat", "P0"],
      "title": "ship feature",
      "content": {
        "type": "Issue",
        "number": 42,
        "title": "ship feature",
        "url": "https://github.com/acme/r/issues/42",
        "repository": "acme/r"
      }
    },
    {
      "id": "PVTI_b",
      "status": "Ready",
      "labels": ["epic"],
      "title": "epic parent",
      "content": {
        "type": "Issue",
        "number": 10,
        "title": "epic parent",
        "url": "https://github.com/acme/r/issues/10",
        "repository": "acme/r"
      }
    },
    {
      "id": "PVTI_c",
      "status": "Done",
      "labels": ["feat"],
      "title": "already done",
      "content": {
        "type": "Issue",
        "number": 7,
        "title": "already done",
        "url": "https://github.com/acme/r/issues/7",
        "repository": "acme/r"
      }
    },
    {
      "id": "PVTI_d",
      "status": "Ready",
      "labels": [],
      "title": "a pr",
      "content": {
        "type": "PullRequest",
        "number": 99,
        "title": "a pr",
        "url": "https://github.com/acme/r/pull/99",
        "repository": "acme/r"
      }
    },
    {
      "id": "PVTI_e",
      "status": "Ready",
      "labels": ["bug"],
      "title": "second ready",
      "content": {
        "type": "Issue",
        "number": 3,
        "title": "second ready",
        "url": "https://github.com/acme/r/issues/3",
        "repository": "acme/r"
      }
    },
    {
      "id": "PVTI_f",
      "status": "Ready",
      "labels": ["bug"],
      "title": "same number, other repository",
      "content": {
        "type": "Issue",
        "number": 42,
        "title": "same number, other repository",
        "url": "https://github.com/other/r/issues/42",
        "repository": "other/r"
      }
    }
  ]
}
JSON
)

  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GH_LOG:-/dev/null}"
if [[ "${1:-} ${2:-}" == "repo view" ]]; then
  printf '%s\n' "${GH_REPOSITORY-acme/r}"
  exit 0
fi
case "${GH_MODE:-ok}" in
  ok)
    printf '%s\n' "${GH_JSON}"
    exit 0
    ;;
  scope)
    echo "Your token has not been granted the required scopes: project" >&2
    exit 1
    ;;
  fail)
    echo "boom" >&2
    exit 1
    ;;
  badjson)
    echo 'not-json'
    exit 0
    ;;
  warn)
    echo "Warning: 4 uncached project items" >&2
    printf '%s\n' "${GH_JSON}"
    exit 0
    ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"

  unset LATTICE_GITHUB_PROJECT_OWNER LATTICE_GITHUB_PROJECT_NUMBER LATTICE_TRIGGER_STATUS
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "missing owner/project → exit 1" {
  run bash "$LIST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"need --owner"* ]] || [[ "$output" == *"LATTICE_GITHUB_PROJECT"* ]]
  [ ! -s "$GH_LOG" ]
}

@test "env owner+number → Ready Issues as tkt-N, skips epic and PR and non-Ready" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST"
  [ "$status" -eq 0 ]
  # order preserved from items array after filters: 42 then 3
  [[ "$output" == $'tkt-42\ntkt-3' ]] || [[ "$output" == $'tkt-42\ntkt-3\n' ]]
  grep -F -e "project item-list 13 --owner acme" "$GH_LOG"
  # Projects filter always quotes status (multi-word columns safe)
  grep -F -e '--query status:"Ready"' "$GH_LOG"
  # epic #10 and Done #7 and PR #99 must not appear
  ! grep -q 'tkt-10' <<<"$output"
  ! grep -q 'tkt-7' <<<"$output"
  ! grep -q 'tkt-99' <<<"$output"
}

@test "default output filters same-number items to the current repository" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^tkt-42$' <<<"$output")" -eq 1 ]
}

@test "items without repository identity are excluded and reported" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  GH_JSON=$(printf '%s' "$GH_JSON" | jq '.items += [{"id":"PVTI_g","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":88,"title":"missing repo","url":"https://github.com/acme/r/issues/88"}}]')
  export GH_JSON
  run bash "$LIST"
  [ "$status" -eq 0 ]
  [[ "$output" != *"tkt-88"* ]]
  [[ "$output" == *"skipped 1 issue item(s) without repository identity"* ]]
}

@test "repository matching is case-insensitive and can be explicit" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST" --repository ACME/R --json
  [ "$status" -eq 0 ]
  echo "$output" | tail -1 | jq -e 'all(.repository == "acme/r")' >/dev/null
}

@test "all-repositories inventory requires json and preserves repository identity" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST" --all-repositories
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires --json"* ]]

  run bash "$LIST" --all-repositories --json
  [ "$status" -eq 0 ]
  json=$(tail -1 <<<"$output")
  echo "$json" | jq -e '[.[] | select(.number == 42) | .repository] | sort == ["acme/r","other/r"]' >/dev/null
  echo "$json" | jq -e 'all(.repository != "")' >/dev/null
}

@test "unresolvable current repository fails closed before listing project items" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  export GH_REPOSITORY=""
  run bash "$LIST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve current repository identity"* ]]
  ! grep -q '^project item-list' "$GH_LOG"
}

@test "--status overrides default Ready" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST" --status Done
  [ "$status" -eq 0 ]
  [[ "$output" == *'tkt-7'* ]]
  ! grep -q 'tkt-42' <<<"$output"
  grep -F -e '--query status:"Done"' "$GH_LOG"
}

@test "missing --owner value → exit 1 (no infinite loop)" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST" --owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a value"* ]]
  [ ! -s "$GH_LOG" ]
}

@test "multi-word --status is quoted in gh --query" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST" --status "In progress"
  [ "$status" -eq 0 ]
  grep -F -e '--query status:"In progress"' "$GH_LOG"
}

@test "LATTICE_TRIGGER_STATUS overrides Ready default" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  export LATTICE_TRIGGER_STATUS=Done
  run bash "$LIST"
  [ "$status" -eq 0 ]
  [[ "$output" == *'tkt-7'* ]]
}

@test "--include-epic keeps epic label Issues" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST" --include-epic
  [ "$status" -eq 0 ]
  [[ "$output" == *'tkt-10'* ]]
  [[ "$output" == *'tkt-42'* ]]
}

@test "--json emits structured candidates" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  run bash "$LIST" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array"' >/dev/null
  echo "$output" | jq -e 'map(.tkt) | index("tkt-42") != null' >/dev/null
  echo "$output" | jq -e 'map(.tkt) | index("tkt-10") == null' >/dev/null
  echo "$output" | jq -e '.[] | select(.tkt=="tkt-42") | .number == 42' >/dev/null
}

@test ".env fills owner/number when flags unset" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=from-file
LATTICE_GITHUB_PROJECT_NUMBER=9
EOF
  run bash "$LIST"
  [ "$status" -eq 0 ]
  grep -F -e "project item-list 9 --owner from-file" "$GH_LOG"
}

@test "cli --owner/--project win over env" {
  export LATTICE_GITHUB_PROJECT_OWNER=env-owner
  export LATTICE_GITHUB_PROJECT_NUMBER=1
  run bash "$LIST" --owner cli-owner --project 99
  [ "$status" -eq 0 ]
  grep -F -e "project item-list 99 --owner cli-owner" "$GH_LOG"
}

@test "gh scope error → exit 1 with hint" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  export GH_MODE=scope
  run bash "$LIST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"project scope"* ]] || [[ "$output" == *"gh auth refresh"* ]]
}

@test "bad JSON shape → exit 1" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  export GH_MODE=badjson
  run bash "$LIST"
  [ "$status" -eq 1 ]
}

@test "gh success-path stderr warning does not break the jq parse" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=13
  export GH_MODE=warn
  run bash "$LIST"
  [ "$status" -eq 0 ]
  [[ "$output" == *'tkt-42'* ]]
  [[ "$output" == *'tkt-3'* ]]
  [[ "$output" != *"jq parse failed"* ]]
}

@test ".env quoted value keeps ' # ' inside quotes; trailing comment after quote dropped" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER="own # er" # real comment
LATTICE_GITHUB_PROJECT_NUMBER=9 # board number
EOF
  run bash "$LIST"
  [ "$status" -eq 0 ]
  grep -F -e "project item-list 9 --owner own # er" "$GH_LOG"
}

@test ".env unquoted value#fragment keeps the hash (no space before #)" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=own#er
LATTICE_GITHUB_PROJECT_NUMBER=9
EOF
  run bash "$LIST"
  [ "$status" -eq 0 ]
  grep -F -e "project item-list 9 --owner own#er" "$GH_LOG"
}
