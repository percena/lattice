#!/usr/bin/env bats
# Tests for auto-stamp-pr-open.sh PostToolUse hook (spc-337 A3 / ADR-012 §1,
# tkt-339): after a `gh pr create` whose response carries a PR URL, run
# stamp-pr-open.sh --pr N from the cwd's repo toplevel. ALWAYS exit 0.
# stamp-pr-open.sh is a recording shim reached through CLAUDE_PLUGIN_ROOT
# pointing at a temp plugin tree.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/auto-stamp-pr-open.sh"

  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/auto-stamp.XXXXXX")"
  REPO="$TDIR/repo"
  git init -q "$REPO"
  git -C "$REPO" symbolic-ref HEAD refs/heads/main
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name t
  git -C "$REPO" commit -q --allow-empty -m init
  mkdir -p "$REPO/.lattice/tickets/tkt-7-demo" "$REPO/sub/dir"

  # Fake plugin root with a recording stamp shim at the path the hook resolves.
  export CLAUDE_PLUGIN_ROOT="$TDIR/plugin"
  mkdir -p "$CLAUDE_PLUGIN_ROOT/skills/_lattice-lib/scripts"
  export CALLS="$TDIR/calls.log"
  : >"$CALLS"
  cat >"$CLAUDE_PLUGIN_ROOT/skills/_lattice-lib/scripts/stamp-pr-open.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$CALLS"
if [[ "${STAMP_FAIL:-}" == "true" ]]; then echo "stamp boom" >&2; exit 1; fi
echo "stamp-pr-open: stamped pr-open (call $(wc -l <"$CALLS" | tr -d ' '))"
EOF
  chmod +x "$CLAUDE_PLUGIN_ROOT/skills/_lattice-lib/scripts/stamp-pr-open.sh"
}

teardown() {
  rm -rf "$TDIR"
}

run_hook() {  # <json>
  printf '%s' "$1" | bash "$HOOK_SCRIPT" 2>&1
}

# Claude Code PostToolUse payload for a Bash call (object-shaped tool_response).
payload() {  # <cwd> <command> <stdout> [stderr]
  jq -cn --arg w "$1" --arg c "$2" --arg o "$3" --arg e "${4:-}" \
    '{session_id:"s1",hook_event_name:"PostToolUse",tool_name:"Bash",cwd:$w,tool_input:{command:$c},tool_response:{stdout:$o,stderr:$e,interrupted:false}}'
}

@test "gh pr create with a PR URL in stdout → stamp invoked once with the right PR + repo, from the toplevel" {
  run run_hook "$(payload "$REPO/sub/dir" "gh pr create --base dev --head tkt-7-demo --title t --body-file b.md" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 1 ]
  grep -qF "$(cd "$REPO" && pwd -P)|--pr 42 --repo acme/widgets" "$CALLS"
  printf '%s\n' "$output" | grep -qF 'stamped pr-open for PR #42'
  printf '%s\n' "$output" | grep -qF '"hookEventName":"PostToolUse"'
}

@test "string-shaped tool_response is handled too" {
  P=$(jq -cn --arg w "$REPO" \
    '{tool_name:"Bash",cwd:$w,tool_input:{command:"gh pr create --fill"},tool_response:"Creating pull request…\nhttps://github.com/acme/widgets/pull/43\n"}')
  run run_hook "$P"
  [ "$status" -eq 0 ]
  grep -qF -- '|--pr 43 --repo acme/widgets' "$CALLS"
}

@test "PR URL in stderr (gh prints progress there) is picked up" {
  run run_hook "$(payload "$REPO" "gh pr create --fill" "" "https://github.com/acme/widgets/pull/44")"
  [ "$status" -eq 0 ]
  grep -qF -- '|--pr 44 --repo acme/widgets' "$CALLS"
}

@test "non-gh command → no-op (exit 0, stamp not called)" {
  run run_hook "$(payload "$REPO" "git status" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  run run_hook "$(payload "$REPO" "gh pr view 42" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "gh pr create without a PR URL in the response (failed create) → no-op" {
  run run_hook "$(payload "$REPO" "gh pr create --fill" "" "pull request create failed: a pull request already exists")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "non-Bash tool → no-op" {
  P=$(jq -cn --arg w "$REPO" '{tool_name:"Read",cwd:$w,tool_input:{file_path:"gh pr create"},tool_response:"https://github.com/acme/widgets/pull/42"}')
  run run_hook "$P"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "malformed JSON → exit 0, stamp not called" {
  run run_hook '{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":"https://github.com/a/b/pull/1"'
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  run run_hook 'gh pr create https://github.com/a/b/pull/1 not json at all'
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  run run_hook ''
  [ "$status" -eq 0 ]
}

@test "cwd without a Lattice home (.lattice/tickets) → no-op" {
  PLAIN="$TDIR/plain"
  git init -q "$PLAIN"
  run run_hook "$(payload "$PLAIN" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  # Not a git work tree at all
  mkdir -p "$TDIR/nogit"
  run run_hook "$(payload "$TDIR/nogit" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "stamp failure → still exit 0 with an advisory naming after-pr-open.sh" {
  run env STAMP_FAIL=true bash -c "printf '%s' '$(payload "$REPO" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")' | bash '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'stamp-pr-open FAILED for PR #42'
  printf '%s\n' "$output" | grep -qF 'after-pr-open.sh --pr 42'
}

@test "missing stamp script under CLAUDE_PLUGIN_ROOT → exit 0 (fail-open advisory)" {
  rm -f "$CLAUDE_PLUGIN_ROOT/skills/_lattice-lib/scripts/stamp-pr-open.sh"
  run run_hook "$(payload "$REPO" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'stamp-pr-open.sh not found'
}

@test "idempotent: a second run for the same PR (script step already stamped) calls the same idempotent stamp again and exits 0" {
  P="$(payload "$REPO" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")"
  run run_hook "$P"
  [ "$status" -eq 0 ]
  run run_hook "$P"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 2 ]
  [ "$(grep -cF -- '|--pr 42 --repo acme/widgets' "$CALLS")" -eq 2 ]
}

@test "first PR URL wins when the response carries several" {
  run run_hook "$(payload "$REPO" "gh pr create --fill" "https://github.com/acme/widgets/pull/42 (see also https://github.com/acme/widgets/pull/41)")"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 1 ]
  grep -qF -- '|--pr 42 --repo acme/widgets' "$CALLS"
}
