#!/usr/bin/env bats
# Tests for auto-stamp-pr-open.sh PostToolUse hook (spc-337 A3 / ADR-012 §1,
# tkt-339): after a `gh pr create` whose response carries a PR URL, run
# stamp-pr-open.sh --pr N from the cwd's repo toplevel. ALWAYS exit 0.
# stamp-pr-open.sh is a recording shim reached through CLAUDE_PLUGIN_ROOT
# pointing at a temp plugin tree; gh is a PATH shim answering `pr view`.
#
# Review cycle 1 (M1): the stamp is BOUND to the PR head branch — the tree the
# command ran in (payload cwd, or a `cd <path> &&` prefix) must have the PR's
# head checked out, else the hook reports "did NOT stamp" and exits 0.

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
  git -C "$REPO" checkout -q -b tkt-7-demo

  # gh shim: `pr view N --json headRefName -q .headRefName` → $GH_HEAD
  STUB_BIN="$TDIR/bin"
  mkdir -p "$STUB_BIN"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"${GH_CALLS:-/dev/null}"
if [[ "${GH_FAIL:-}" == "true" ]]; then exit 1; fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then printf '%s\n' "${GH_HEAD:-}"; exit 0; fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  export GH_HEAD="tkt-7-demo"
  export GH_CALLS="$TDIR/gh.log"
  : >"$GH_CALLS"

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
  printf '%s\n' "$output" | grep -qF "stamped pr-open for PR #42 (acme/widgets) on branch 'tkt-7-demo'"
  printf '%s\n' "$output" | grep -qF '"hookEventName":"PostToolUse"'
  # --head in the command settles the head branch without a gh round-trip.
  [ ! -s "$GH_CALLS" ]
}

@test "without --head the PR head comes from gh pr view; match → stamped" {
  run run_hook "$(payload "$REPO" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  grep -qF -- '|--pr 42 --repo acme/widgets' "$CALLS"
  grep -qF 'gh pr view 42 --repo acme/widgets --json headRefName' "$GH_CALLS"
}

@test "M1(a): current branch ≠ PR head → NOT stamped, honest context, exit 0" {
  export GH_HEAD="tkt-11-other"
  run run_hook "$(payload "$REPO" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  printf '%s\n' "$output" | grep -qF "did NOT stamp pr-open for PR #42"
  printf '%s\n' "$output" | grep -qF "current branch 'tkt-7-demo'"
  printf '%s\n' "$output" | grep -qF "PR head 'tkt-11-other'"
  printf '%s\n' "$output" | grep -qF 'after-pr-open.sh --pr 42'
  if printf '%s\n' "$output" | grep -qE 'PostToolUse stamped'; then false; fi
  # Explicit --head that disagrees with the tree is refused the same way.
  run run_hook "$(payload "$REPO" "gh pr create --head tkt-11-other --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  printf '%s\n' "$output" | grep -qF "did NOT stamp"
}

@test "M1(a): cd ../other && gh pr create → stamps in the OTHER worktree only when its branch matches" {
  git -C "$REPO" worktree add -q "$TDIR/tkt-8-x" -b tkt-8-x
  mkdir -p "$TDIR/tkt-8-x/.lattice/tickets"
  # session cwd = tkt-7 tree; command moved to the tkt-8 tree and opened tkt-8's PR
  run run_hook "$(payload "$REPO" "cd ../tkt-8-x && gh pr create --base dev --head tkt-8-x --fill" "https://github.com/acme/widgets/pull/80")"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 1 ]
  grep -qF "$(cd "$TDIR/tkt-8-x" && pwd -P)|--pr 80 --repo acme/widgets" "$CALLS"
  if grep -qF "$(cd "$REPO" && pwd -P)|" "$CALLS"; then false; fi
  printf '%s\n' "$output" | grep -qF "on branch 'tkt-8-x'"
  # Same cd prefix, but the PR head is a third branch → the other tree is NOT stamped either.
  : >"$CALLS"
  run run_hook "$(payload "$REPO" "cd ../tkt-8-x && gh pr create --head tkt-9-z --fill" "https://github.com/acme/widgets/pull/81")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  printf '%s\n' "$output" | grep -qF "current branch 'tkt-8-x'"
  printf '%s\n' "$output" | grep -qF "PR head 'tkt-9-z'"
  # Quoted and ;-separated cd forms resolve the same tree.
  : >"$CALLS"
  run run_hook "$(payload "$REPO/sub/dir" "cd \"../../../tkt-8-x\"; gh pr create --head=tkt-8-x --fill" "https://github.com/acme/widgets/pull/80")"
  [ "$status" -eq 0 ]
  grep -qF "$(cd "$TDIR/tkt-8-x" && pwd -P)|--pr 80 --repo acme/widgets" "$CALLS"
  git -C "$REPO" worktree remove --force "$TDIR/tkt-8-x"
}

@test "M1(b): main clone on dev → 'did NOT stamp' wording, never 'stamped'" {
  git -C "$REPO" checkout -q -b dev
  run run_hook "$(payload "$REPO" "gh pr create --head tkt-7-demo --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  printf '%s\n' "$output" | grep -qF "did NOT stamp pr-open for PR #42"
  printf '%s\n' "$output" | grep -qF "current branch 'dev'"
  if printf '%s\n' "$output" | grep -qE 'PostToolUse stamped'; then false; fi
}

@test "M1(b): a no-binder skip from stamp-pr-open is reported as NOT stamped" {
  cat >"$CLAUDE_PLUGIN_ROOT/skills/_lattice-lib/scripts/stamp-pr-open.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$CALLS"
echo "stamp-pr-open: no binder at $PWD/.lattice/tickets/tkt-7-demo/README.md — skip (ticket-only flow)"
exit 0
EOF
  run run_hook "$(payload "$REPO" "gh pr create --head tkt-7-demo --fill" "https://github.com/acme/widgets/pull/42")"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "did NOT stamp pr-open for PR #42"
  printf '%s\n' "$output" | grep -qF "skip (ticket-only flow)"
  if printf '%s\n' "$output" | grep -qE 'PostToolUse stamped'; then false; fi
}

@test "unknown PR head (no --head, gh fails) → NOT stamped, exit 0" {
  run env GH_FAIL=true bash -c "printf '%s' '$(payload "$REPO" "gh pr create --fill" "https://github.com/acme/widgets/pull/42")' | bash '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  printf '%s\n' "$output" | grep -qF "did NOT stamp pr-open for PR #42"
  printf '%s\n' "$output" | grep -qF "could not determine the PR head branch"
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
