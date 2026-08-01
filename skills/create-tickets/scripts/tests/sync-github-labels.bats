#!/usr/bin/env bats
# Tests for sync-github-labels.sh using a stubbed gh on PATH.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export SYNC="$REPO_ROOT/skills/create-tickets/scripts/sync-github-labels.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gh-labels.XXXXXX")"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export GH_CALL_LOG="$TEST_DIR/gh-calls.log"
  export GH_LIST_FILE="$TEST_DIR/gh-list.txt"
  export GH_LIST_FAIL=""
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$GH_CALL_LOG"
case "$1 $2" in
  "api --paginate")
    if [[ -n "${GH_LIST_FAIL:-}" ]]; then exit 1; fi
    cat "$GH_LIST_FILE"
    ;;
  "label create"|"label edit")
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "fetches the label list exactly once, paginated" {
  : >"$GH_LIST_FILE"
  run bash "$SYNC"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^api --paginate' "$GH_CALL_LOG")" -eq 1 ]
}

@test "existing label beyond a 1000-name page is still detected" {
  # 1200 filler names, catalog labels appended after the old --limit horizon
  seq -f 'zz-filler-%g' 1 1200 >"$GH_LIST_FILE"
  printf 'feat\nP0\n' >>"$GH_LIST_FILE"
  run bash "$SYNC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exists:  feat"* ]]
  [[ "$output" == *"exists:  P0"* ]]
  ! grep -q '^label create feat' "$GH_CALL_LOG"
  ! grep -q '^label create P0' "$GH_CALL_LOG"
}

@test "creates missing labels and skips existing ones" {
  printf 'feat\nbug\n' >"$GH_LIST_FILE"
  run bash "$SYNC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exists:  feat"* ]]
  [[ "$output" == *"exists:  bug"* ]]
  [[ "$output" == *"created: chore"* ]]
  [[ "$output" == *"created: P0"* ]]
  # 13 catalog labels, 2 already exist
  [ "$(grep -c '^label create' "$GH_CALL_LOG")" -eq 11 ]
}

@test "--force-color edits existing labels instead of skipping" {
  printf 'feat\n' >"$GH_LIST_FILE"
  run bash "$SYNC" --force-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated: feat"* ]]
  [ "$(grep -c '^label edit' "$GH_CALL_LOG")" -eq 1 ]
}

@test "aborts without creating anything when label list fails" {
  export GH_LIST_FAIL=1
  run bash "$SYNC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborting"* ]]
  ! grep -q '^label create' "$GH_CALL_LOG"
}
