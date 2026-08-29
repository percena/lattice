#!/usr/bin/env bats
# Tests for lattice-lib github-issue-parent-add.sh (stubbed gh; no network).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export ADD="$REPO_ROOT/skills/_lattice-lib/scripts/github-issue-parent-add.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gipa.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cd "$MAIN"

  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export GH_MODE="set_parent_ok"
  export GH_LOG="$TEST_DIR/gh.log"
  : >"$GH_LOG"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GH_LOG:-/dev/null}"
mode="${GH_MODE:-set_parent_ok}"
# issue edit --help detection
if [[ "$*" == "issue edit --help" ]]; then
  case "$mode" in
    no_flags) echo "USAGE: gh issue edit {<number> | <url>} [flags]"; exit 0 ;;
    *)
      echo "USAGE: gh issue edit {<number> | <url>} [flags]"
      echo "  --set-parent number     Set parent issue"
      echo "  --add-sub-issue numbers Add sub-issues"
      exit 0
      ;;
  esac
fi
case "$mode" in
  set_parent_ok)
    if [[ "$*" == issue\ edit\ *--set-parent* ]]; then exit 0; fi
    exit 1
    ;;
  add_sub_ok)
    if [[ "$*" == issue\ edit\ *--add-sub-issue* ]]; then exit 0; fi
    # make --set-parent fail so path 2 is used
    if [[ "$*" == issue\ edit\ *--set-parent* ]]; then echo fail >&2; exit 1; fi
    exit 1
    ;;
  already)
    echo "issue is already a sub-issue of that parent" >&2
    exit 1
    ;;
  already_different_parent)
    echo "child issue already has a parent (#99)" >&2
    exit 1
    ;;
  already_ambiguous)
    echo "link already pending review" >&2
    exit 1
    ;;
  graphql_ok)
    if [[ "$*" == issue\ edit\ * ]]; then echo no >&2; exit 1; fi
    if [[ "$1" == "api" && "$*" == *graphql* ]]; then
      echo '{"data":{"addSubIssue":{"issue":{"number":10},"subIssue":{"number":11}}}}'
      exit 0
    fi
    if [[ "$*" == issue\ view* ]]; then
      # two calls — parent then child; return stable-looking ids
      if [[ "$*" == *\ 10\ * || "$*" == *" 10"* ]]; then
        echo '{"id":"I_parent","number":10}'
      else
        echo '{"id":"I_child","number":11}'
      fi
      exit 0
    fi
    exit 1
    ;;
  rest_ok)
    if [[ "$*" == issue\ edit\ * ]]; then echo no >&2; exit 1; fi
    if [[ "$*" == *graphql* ]]; then echo gql fail >&2; exit 1; fi
    if [[ "$*" == issue\ view* ]]; then
      echo '{"id":"I_x","number":1}'; exit 0
    fi
    if [[ "$*" == repo\ view* ]]; then
      echo 'acme/r'; exit 0
    fi
    # gh api repos/.../issues/N  → database id
    if [[ "$1" == "api" && "$*" != *graphql* && "$*" != *sub_issues* ]]; then
      echo '3000028010'; exit 0
    fi
    if [[ "$1" == "api" && "$*" == *sub_issues* ]]; then
      echo '{"id":1}'; exit 0
    fi
    exit 1
    ;;
  all_fail)
    echo "boom" >&2
    exit 1
    ;;
  numeric_id_gql_skip_rest_ok)
    # gh issue view returns a numeric id (database id, not node id) —
    # the guard must skip GraphQL and fall through to REST.
    if [[ "$*" == issue\ edit\ * ]]; then echo no >&2; exit 1; fi
    if [[ "$*" == *graphql* ]]; then echo "should not reach GraphQL" >&2; exit 1; fi
    if [[ "$*" == issue\ view* ]]; then
      echo '{"id":"187","number":10}'
      exit 0
    fi
    if [[ "$*" == repo\ view* ]]; then
      echo 'acme/r'; exit 0
    fi
    if [[ "$1" == "api" && "$*" != *graphql* && "$*" != *sub_issues* ]]; then
      echo '3000028010'; exit 0
    fi
    if [[ "$1" == "api" && "$*" == *sub_issues* ]]; then
      echo '{"id":1}'; exit 0
    fi
    exit 1
    ;;
esac
exit 0
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "missing args → soft skip" {
  run bash "$ADD"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "need --parent and --child"
}

@test "same parent and child → skip" {
  run bash "$ADD" --parent 5 --child 5
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "same"
}

@test "gh --set-parent path when flag present" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '\-\-set\-parent|linked\ via\ gh\ \-\-set\-parent'
  grep -F -e "issue edit 11 --set-parent 10" "$GH_LOG"
}

@test "falls back to --add-sub-issue" {
  export GH_MODE=add_sub_ok
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "linked via gh --add-sub-issue"
  grep -F -e "issue edit 10 --add-sub-issue 11" "$GH_LOG"
}

@test "already linked treated as success" {
  export GH_MODE=already
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "already"
}

@test "GraphQL fallback when no edit flags succeed" {
  export GH_MODE=graphql_ok
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "GraphQL"
  grep -F graphql "$GH_LOG"
}

@test "REST fallback when GraphQL fails" {
  export GH_MODE=rest_ok
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "REST"
  grep -F sub_issues "$GH_LOG"
}

@test "REST fallback sends sub_issue_id as typed -F field (integer, not string)" {
  # -f would post a string; the endpoint requires an integer (422 otherwise).
  export GH_MODE=rest_ok
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  grep -F -e "-F sub_issue_id=3000028010" "$GH_LOG"
  if grep -F -e "-f sub_issue_id=" "$GH_LOG"; then false; fi
}

@test "numeric id field skips GraphQL, falls through to REST" {
  # gh issue view returns a numeric id (database id) in the id field —
  # the guard must skip GraphQL (which would fail with "Could not resolve
  # to a node with the global id of '187'") and use REST instead.
  export GH_MODE=numeric_id_gql_skip_rest_ok
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "numeric"
  printf '%s\n' "$output" | grep -qF "REST"
  # GraphQL must NOT have been called
  if grep -F graphql "$GH_LOG"; then false; fi
}

@test "URL forms parse numbers" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" \
    --parent "https://github.com/acme/r/issues/10" \
    --child "https://github.com/acme/r/issues/11"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "linked via gh --set-parent"
  grep -F -e "issue edit" "$GH_LOG" | grep -F -e "11" | grep -F -e "10"
}

@test "all failure modes still exit 0" {
  export GH_MODE=all_fail
  run bash "$ADD" --parent 1 --child 2
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'non\-fatal|failed|skip|already|linked|GraphQL|REST|gh\ issue\ edit\ failed|parent\ link\ failed'
}

@test "positional parent child works" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" 3 4
  [ "$status" -eq 0 ]
  grep -F -e "issue edit 4 --set-parent 3" "$GH_LOG"
}

@test "missing --parent value → exit 0 (no hang)" {
  # Regression: shift 2 || true with only --parent never advanced argv.
  run bash "$ADD" --parent
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "requires a value"
  [ ! -s "$GH_LOG" ]
}

@test "missing --child value → exit 0 (no hang)" {
  run bash "$ADD" --parent 10 --child
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "requires a value"
  [ ! -s "$GH_LOG" ]
}

@test "PR URL is refused — trailing digits never parsed as an issue number" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" --parent "https://github.com/acme/r/pull/10" --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "not a GitHub /issues/ URL"
  printf '%s\n' "$output" | grep -qF "cannot parse parent issue number"
  [ ! -s "$GH_LOG" ]
}

@test "discussions URL is refused like a PR URL" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" --parent 10 --child "https://github.com/acme/r/discussions/11"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "not a GitHub /issues/ URL"
  printf '%s\n' "$output" | grep -qF "cannot parse child issue number"
  [ ! -s "$GH_LOG" ]
}

@test "non-URL trailing-digit inputs (tkt-N style) still parse" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" --parent tkt-10 --child 11
  [ "$status" -eq 0 ]
  grep -F -e "issue edit 11 --set-parent 10" "$GH_LOG"
}

@test "different-parent conflict is a failure, not idempotent success" {
  export GH_MODE=already_different_parent
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -F "already linked")" ]
  printf '%s\n' "$output" | grep -qF "gh issue edit failed"
}

@test "ambiguous already-message is logged as ambiguous, never success" {
  export GH_MODE=already_ambiguous
  run bash "$ADD" --parent 10 --child 11
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -F "already linked")" ]
  printf '%s\n' "$output" | grep -qF "parent link attempt ambiguous: link already pending review"
}

@test "cross-repository parent/child URLs are refused before mutation" {
  export GH_MODE=set_parent_ok
  run bash "$ADD"     --parent "https://github.com/owner/a/issues/10"     --child "https://github.com/owner/b/issues/11"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cross-repository parent/child refused"
  # soft-fail exit 0; no mutation flags
  if [[ -f "$GH_LOG" ]]; then
    if grep -E "set-parent|add-sub-issue|sub_issues|graphql" "$GH_LOG"; then false; fi
  fi
}

@test "SSH-remote PR URL is refused — @host: form cannot reach the digits fallback" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" --parent "git@github.com:acme/r/pull/10" --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "not a GitHub /issues/ URL"
  [ ! -s "$GH_LOG" ]
}

@test "case-variant bare-host PR URL is refused" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" --parent "GitHub.com/acme/r/pull/10" --child 11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "not a GitHub /issues/ URL"
  [ ! -s "$GH_LOG" ]
}

@test "SSH-form issues URL still carries the cross-repo guard" {
  export GH_MODE=set_parent_ok
  run bash "$ADD" --parent "git@github.com:acme/r/issues/10" --child "https://github.com/other/r2/issues/11"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cross-repository parent/child refused"
  [ ! -s "$GH_LOG" ]
}
