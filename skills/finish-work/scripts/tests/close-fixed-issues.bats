#!/usr/bin/env bats
# Tests for close-fixed-issues.sh (Fixes parsing + dry-run; no live gh required)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export CLOSE="$REPO_ROOT/skills/finish-work/scripts/close-fixed-issues.sh"
}

@test "extracts Fixes/Closes/Resolves and ignores Refs" {
  body=$(cat <<'EOF'
## Lineage

Fixes #7
Fixes #8
Closes #9
Resolves #10
Refs #99
See also #12 in prose should not match alone
EOF
)
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[7,8,9,10]'
  [ -z "$(printf '%s\n' "$output" | grep -F '"closing_ids":[7,8,9,10,99]')" ]
  [ -z "$(printf '%s\n' "$output" | grep -F ',12,')" ]
  printf '%s\n' "$output" | grep -qF '"dry_run":true'
}

@test "case-insensitive keywords" {
  body=$'fixes #3\nCLOSES #2\nResolves #1\n'
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[1,2,3]'
}

@test "dedupes repeated Fixes" {
  body=$'Fixes #5\nFixes #5\nFixes #4\n'
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[4,5]'
}

@test "empty body is ok with empty candidates" {
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"no keywords here"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[]'
  printf '%s\n' "$output" | grep -qF '"ok":true'
}

@test "body-file path works" {
  f=$(mktemp)
  printf 'Fixes #42\nRefs #7\n' >"$f"
  run bash "$CLOSE" --body-file "$f" --dry-run --json
  rm -f "$f"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[42]'
}

@test "live close without --pr is rejected" {
  run bash "$CLOSE" --body-stdin <<<"Fixes #1"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "only support --dry-run" || printf '%s\n' "$stderr" | grep -qF "only support --dry-run"
}

make_fake_gh() {
  # Always self-managed per call: a shared BATS_TEST_TMPDIR (pre-1.4 bats
  # shims set one dir per suite, not per test) would accumulate gh.log
  # across tests and false-fail the dry-run log assertions.
  local tmp
  tmp="$(mktemp -d)"
  export FAKE_GH_LOG="$tmp/gh.log"
  export GH_BIN="$tmp/gh"
  cat >"$GH_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
case "${1:-} ${2:-}" in
  "pr view")
    if [[ "${FAKE_PR_VIEW_FAIL:-false}" == "true" ]]; then
      exit 1
    fi
    python3 - <<'PY'
import json, os
print(json.dumps({
    "body": os.environ.get("FAKE_PR_BODY", "Fixes #7"),
    "url": "https://github.com/percena/lattice/pull/99",
    "baseRefName": "dev",
    "state": os.environ.get("FAKE_PR_STATE", "MERGED"),
    "mergedAt": os.environ.get("FAKE_PR_MERGED_AT", "2026-07-27T00:00:00Z"),
}))
PY
    ;;
  "repo view")
    printf '%s\n' 'dev'
    ;;
  "issue view")
    python3 - <<'PY'
import json, os
labels = [{"name": "epic"}] if os.environ.get("FAKE_ISSUE_EPIC") == "true" else []
print(json.dumps({"state": os.environ.get("FAKE_ISSUE_STATE", "OPEN"), "labels": labels}))
PY
    ;;
  "issue close")
    ;;
  *)
    printf 'unexpected fake gh invocation: %s\n' "$*" >&2
    exit 9
    ;;
esac
EOF
  chmod +x "$GH_BIN"
}

assert_log_lacks() {
  local pattern="$1"
  if grep -Eq "$pattern" "$FAKE_GH_LOG"; then
    printf 'unexpected fake gh call matching %s:\n' "$pattern" >&2
    grep -E "$pattern" "$FAKE_GH_LOG" >&2 || true
    return 1
  fi
}

@test "human dry-run lists candidates" {
  run bash "$CLOSE" --body-stdin --dry-run <<<"Fixes #7"$'\n'"Fixes #8"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "candidates: 7 8"
  printf '%s\n' "$output" | grep -qF "dry_run: true"
}

@test "ignores fenced directives in containers and does not accept trailing-text closers" {
  body=$'Fixes #3\n> ````markdown\n> Fixes #7\n> ```\n>     ````\n> Closes #8\n> ~~~~\n> Resolves #9\n> ````\n- ~~~\n  Fixes #10\n  ~~~\nResolves #4\n> ```markdown\n> example only\nFixes #11\n- ~~~\n  example only\nFixes #12\n- Example\n    ```text\n    Fixes #41\n    ```\nFixes #42\n```bad`info\nFixes #13\n```\n'
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[3,4,11,12,13,42]'
}

@test "does not coerce repository-qualified closing references to local ids" {
  body=$'Fixes owner/other#8\nCloses #7\n'
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[7]'
  printf '%s\n' "$output" | grep -qF '"unsupported_references":["owner/other#8"]'
}

@test "matches GitHub's full closing keyword grammar (tense + colon forms)" {
  body=$'Fixed #12\nfix #13\nCloses: #14\nclose #15\nresolved #16\nResolve #17\nclosed #18\n'
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[12,13,14,15,16,17,18]'
}

@test "hyphen compounds and inline code spans are prose, not directives" {
  body=$'This auto-closes #5 once deployed\nre-fixes #6 the regression\nUse `Fixes #55` in the body\nFixes #9\n'
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[9]'
}

@test "issue-URL closing forms are unsupported references, not silently ignored" {
  body=$'Fixes https://github.com/owner/other/issues/15\nCloses #7\n'
  run bash "$CLOSE" --body-stdin --dry-run --json <<<"$body"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[7]'
  printf '%s\n' "$output" | grep -qF 'https://github.com/owner/other/issues/15'
}

@test "missing extractor lib hard-fails instead of reporting ok with zero ids" {
  # Own mktemp dir: BATS_TEST_TMPDIR is unset before bats 1.4 and would
  # expand these paths into /.
  tmp=$(mktemp -d)
  cp "$CLOSE" "$tmp/close.sh"
  run bash "$tmp/close.sh" --body-stdin --dry-run --json <<<"Fixes #7"
  rm -rf "$tmp"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF '"ok":false'
  printf '%s\n' "$output" | grep -qF 'closing_extractor_failed'
}

@test "broken python3 hard-fails instead of reporting ok with zero ids" {
  tmp=$(mktemp -d)
  printf '#!/usr/bin/env bash\nexit 1\n' >"$tmp/python3"
  chmod +x "$tmp/python3"
  PATH="$tmp:$PATH" run bash "$CLOSE" --body-stdin --dry-run <<<"Fixes #7"
  rm -rf "$tmp"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "closing directive extractor failed"
}

@test "OPEN PR fails closed without reading or closing issues" {
  make_fake_gh
  export FAKE_PR_STATE="OPEN"
  export FAKE_PR_MERGED_AT=""
  export FAKE_PR_BODY="Fixes #7"

  run bash "$CLOSE" --pr 99 --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"ok":false'
  printf '%s\n' "$output" | grep -qF '"reason":"pr_not_merged"'
  printf '%s\n' "$output" | grep -qF '"pr_state":"OPEN"'
  assert_log_lacks '^issue (view|close)' || return 1
}

@test "unavailable PR metadata returns a structured failure without issue calls" {
  make_fake_gh
  export FAKE_PR_VIEW_FAIL="true"

  run bash "$CLOSE" --pr 99 --json
  [ "$status" -eq 2 ]
  assert_log_lacks '^issue (view|close)' || return 1
  printf '%s\n' "$output" | grep -qF '"ok":false'
  printf '%s\n' "$output" | grep -qF '"reason":"pr_metadata_unavailable"'
}

@test "closed ambiguous or undated merged PR fails closed" {
  make_fake_gh
  export FAKE_PR_BODY="Fixes #7"

  for scenario in 'CLOSED|' '|2026-07-27T00:00:00Z' 'MERGED|' 'OPEN|2026-07-27T00:00:00Z'; do
    export FAKE_PR_STATE="${scenario%%|*}"
    export FAKE_PR_MERGED_AT="${scenario#*|}"
    run bash "$CLOSE" --pr 99 --json
    if [[ "$status" -ne 1 || "$output" != *'"reason":"pr_not_merged"'* ]]; then
      printf 'scenario %s unexpectedly returned status=%s output=%s\n' "$scenario" "$status" "$output" >&2
      return 1
    fi
    if [[ "$scenario" == OPEN\|* && "$output" != *'"note":"refusing issue mutation: PR state is '\''OPEN'\'' and mergedAt is present"'* ]]; then
      printf 'inconsistent merge evidence note: %s\n' "$output" >&2
      return 1
    fi
  done
  assert_log_lacks '^issue (view|close)' || return 1
}

@test "merged PR skips epic issues without closing them" {
  make_fake_gh
  export FAKE_PR_STATE="MERGED"
  export FAKE_PR_MERGED_AT="2026-07-27T00:00:00Z"
  export FAKE_PR_BODY="Fixes #7"
  export FAKE_ISSUE_EPIC="true"

  run bash "$CLOSE" --pr 99 --expected-closing-ids 7 --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"skipped_epic":[7]'
  assert_log_lacks '^issue close' || return 1
}

@test "merged PR closes a normal open delivery issue" {
  make_fake_gh
  export FAKE_PR_STATE="MERGED"
  export FAKE_PR_MERGED_AT="2026-07-27T00:00:00Z"
  export FAKE_PR_BODY="Fixes #7"
  export FAKE_ISSUE_EPIC="false"
  export FAKE_ISSUE_STATE="OPEN"

  run bash "$CLOSE" --pr 99 --expected-closing-ids 7 --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closed":[7]'
  grep -q '^issue close 7 ' "$FAKE_GH_LOG"
}

@test "live close requires a pre-merge approved closing-id set" {
  make_fake_gh
  export FAKE_PR_BODY="Fixes #7"

  run bash "$CLOSE" --pr 99 --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason":"expected_closing_ids_required"'
  assert_log_lacks '^issue (view|close)' || return 1
}

@test "same approved set succeeds despite reorder and duplicates" {
  make_fake_gh
  export FAKE_PR_BODY=$'Fixes #8\nFixes #7\nFixes #8'

  run bash "$CLOSE" --pr 99 --expected-closing-ids '8,7,8' --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"closing_ids":[7,8]'
  printf '%s\n' "$output" | grep -qF '"expected_closing_ids":[7,8]'
  grep -q '^issue close 7 ' "$FAKE_GH_LOG"
  grep -q '^issue close 8 ' "$FAKE_GH_LOG"
}

@test "added or removed closing id fails before any issue lookup" {
  make_fake_gh
  export FAKE_PR_BODY=$'Fixes #7\nFixes #8'

  run bash "$CLOSE" --pr 99 --expected-closing-ids 7 --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason":"closing_set_changed"'
  assert_log_lacks '^issue (view|close)' || return 1
}

@test "empty approved set cannot be expanded after merge" {
  make_fake_gh
  export FAKE_PR_BODY="Fixes #7"

  run bash "$CLOSE" --pr 99 --expected-closing-ids '' --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason":"closing_set_changed"'
  assert_log_lacks '^issue (view|close)' || return 1
}
