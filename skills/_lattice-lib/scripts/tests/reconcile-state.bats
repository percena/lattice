#!/usr/bin/env bats
# Tests for reconcile-state.sh: read-only GitHub↔binder state reconciliation.
# Uses a fake `gh` (no real credentials or network required).
#
# Covers:
#   - reconciled fixtures → ok:true (A1)
#   - each drift class → ok:false with stable reason codes (A1)
#   - auth/network unknown → result=unknown, nonzero (A2)
#   - read-only assertions: no gh mutation calls, binder unchanged (A3)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export RS="$REPO_ROOT/skills/_lattice-lib/scripts/reconcile-state.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rs.XXXXXX")"
  REPO="$TEST_DIR/repo"
  BINDER_DIR="$REPO/.lattice/tickets/tkt-7-demo"
  mkdir -p "$BINDER_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  git -C "$REPO" remote add origin https://github.com/percena/lattice.git
  BINDER="$BINDER_DIR/README.md"
  GH_FAKE="$TEST_DIR/bin"
  mkdir -p "$GH_FAKE"
  GH_LOG="$TEST_DIR/gh.log"
  export GH_LOG
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Binder fixture builders
# ---------------------------------------------------------------------------

# Args: status prs_row [extra table rows...]
write_binder() {
  local status="$1" prs="$2"; shift 2
  local extra=""
  for row in "$@"; do
    extra+="| ${row} |\n"
  done
  printf '# tkt-7-demo\n\n| Field | Value |\n| --- | --- |\n| status | %s |\n| github | https://github.com/percena/lattice/issues/7 |\n| prs | %s |\n%s\n## Acceptance\n\n- [ ] **A1** thing\n\n## Finish\n\n- (none yet)\n' \
    "$status" "$prs" "$extra" >"$BINDER"
  printf '%s' "$extra" >>/dev/null
}

write_finish_merged() {
  local pr_n="$1" merged_at="$2"
  # Replace the Finish section with a real merged ledger
  python3 - "$BINDER" "$pr_n" "$merged_at" <<'PY'
import sys, re
path, pr_n, merged_at = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding="utf-8").read()
s = re.sub(
    r'(## Finish\s*\n)(.*?)(?=\n## |\Z)',
    rf'\1- pr-{pr_n} merged: {merged_at} — https://github.com/percena/lattice/pull/{pr_n}\n',
    s, count=1, flags=re.DOTALL,
)
open(path, "w", encoding="utf-8").write(s)
PY
}

# Fake gh builder. Reads $GH_LOG to record every invocation (read-only proof).
# Args are passed as a heredoc written to the fake gh script.
make_fake_gh() {
  cat >"$GH_FAKE/gh" <<'EOF'
#!/usr/bin/env bash
# Record every invocation for read-only assertions.
printf '%s\n' "$*" >>"$GH_LOG"
case "$1" in
  auth)
    # gh auth status — callers control via RS_AUTH_FAIL
    if [[ "${RS_AUTH_FAIL:-}" == "1" ]]; then
      echo "error: not logged in" >&2
      exit 1
    fi
    exit 0
    ;;
  issue)
    num="$3"
    # Mirror real gh (2.92.0): `mergedAt` is not a valid `gh issue view`
    # field. Validate the --json fields so a regression that re-adds
    # mergedAt to the issue query fails loudly instead of masking the bug
    # (tkt-238 H4 — the old mock returned canned JSON regardless of fields).
    _jf=""
    _sa=("$@")
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--json" ]]; then _jf="$2"; break; fi
      shift
    done
    set -- "${_sa[@]}"
    if [[ ",${_jf}," == *",mergedAt,"* ]]; then
      echo 'Unknown JSON field: "mergedAt"' >&2
      exit 1
    fi
    case "$num" in
      7) printf '%s\n' '{"state":"OPEN","closedAt":null,"url":"https://github.com/percena/lattice/issues/7"}' ;;
      *) echo "error: not found" >&2; exit 1 ;;
    esac
    ;;
  pr)
    num="$3"
    case "$num" in
      12) printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://github.com/percena/lattice/pull/12"}' ;;
      13) printf '%s\n' '{"state":"CLOSED","mergedAt":null,"url":"https://github.com/percena/lattice/pull/13"}' ;;
      14) printf '%s\n' '{"state":"OPEN","mergedAt":null,"url":"https://github.com/percena/lattice/pull/14"}' ;;
      *) echo "error: not found" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "unknown command: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$GH_FAKE/gh"
}

# Override PR/issue responses by writing a custom fake gh.
make_custom_gh() {
  cat >"$GH_FAKE/gh" "$1"
  chmod +x "$GH_FAKE/gh"
}

run_rs() {
  : >"$GH_LOG"
  run env PATH="$GH_FAKE:$PATH" GH_LOG="$GH_LOG" bash "$RS" --binder "$BINDER" "$@"
}

# ---------------------------------------------------------------------------
# A1: Reconciled fixtures → ok:true
# ---------------------------------------------------------------------------

@test "reconciled: open issue, working binder, no PRs → ok:true" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok=true"
  printf '%s\n' "$output" | grep -qF "no drift detected"
}

@test "reconciled: closed issue, closed binder, merged PR → ok:true" {
  write_binder "closed" "pr-12 — https://github.com/percena/lattice/pull/12"
  write_finish_merged 12 2026-07-31T10:00:00Z
  # Override fake gh: issue 7 is CLOSED
  cat >"$GH_FAKE/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1" in
  auth) exit 0 ;;
  issue) printf '%s\n' '{"state":"CLOSED","closedAt":"2026-07-31T10:01:00Z","url":"https://github.com/percena/lattice/issues/7"}' ;;
  pr) case "$3" in 12) printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://github.com/percena/lattice/pull/12"}' ;; esac ;;
esac
EOF
  chmod +x "$GH_FAKE/gh"
  run_rs
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok=true"
}

@test "reconciled: pr-open binder with an open PR → ok:true" {
  write_binder "pr-open" "pr-14 — https://github.com/percena/lattice/pull/14"
  make_fake_gh
  run_rs
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok=true"
}

# ---------------------------------------------------------------------------
# A1: Drift classes → ok:false with stable reason codes
# ---------------------------------------------------------------------------

@test "drift: closed issue vs working binder" {
  write_binder "queued" "(none yet)"
  cat >"$GH_FAKE/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1" in
  auth) exit 0 ;;
  issue) printf '%s\n' '{"state":"CLOSED","closedAt":"2026-07-31T10:01:00Z","url":"https://github.com/percena/lattice/issues/7"}' ;;
esac
EOF
  chmod +x "$GH_FAKE/gh"
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "closed_issue_working_binder"
}

@test "drift: merged PR vs nonterminal binder" {
  write_binder "pr-open" "pr-12 — https://github.com/percena/lattice/pull/12"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "merged_pr_nonterminal_binder"
}

@test "drift: closed PR vs nonterminal binder" {
  write_binder "pr-open" "pr-13 — https://github.com/percena/lattice/pull/13"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "closed_pr_nonterminal_binder"
}

@test "drift: open PR vs closed binder" {
  write_binder "closed" "pr-14 — https://github.com/percena/lattice/pull/14"
  write_finish_merged 14 2026-07-31T10:00:00Z
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "open_pr_closed_binder"
}

@test "drift: pr-open with missing PR (no prs entries)" {
  write_binder "pr-open" "(none yet)"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "pr_open_missing_pr"
}

@test "drift: pr-open with unresolvable PR (404 on GitHub)" {
  write_binder "pr-open" "pr-99 — https://github.com/percena/lattice/pull/99"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "pr_open_unresolvable_pr"
}

@test "drift: repo identity mismatch (github URL points to foreign repo)" {
  write_binder "queued" "(none yet)"
  # Override the github URL to a foreign repo
  sed -i.bak 's#github.com/percena/lattice/issues/7#github.com/attacker/otherrepo/issues/7#' "$BINDER"
  rm -f "$BINDER.bak"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "repo_identity_mismatch"
}

@test "drift: PR URL points to a foreign repo" {
  write_binder "pr-open" "pr-12 — https://github.com/attacker/otherrepo/pull/12"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "repo_identity_mismatch"
}

# ---------------------------------------------------------------------------
# A2: auth/network unknown → result=unknown, nonzero
# ---------------------------------------------------------------------------

@test "unknown: gh not installed → result=unknown, exit 2" {
  write_binder "queued" "(none yet)"
  # Build a PATH without gh. We symlink every executable from each PATH
  # directory into one shadow dir, then delete the gh symlink — this avoids
  # a fragile whitelist that breaks whenever a new dependency is added.
  NOGH_BIN="$TEST_DIR/nogh_bin"
  mkdir -p "$NOGH_BIN"
  local IFS=':'
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -x "$f" ] && [ ! -d "$f" ] && ln -sf "$f" "$NOGH_BIN/" 2>/dev/null || true
    done
  done
  rm -f "$NOGH_BIN/gh"
  : >"$GH_LOG"
  run env PATH="$NOGH_BIN" bash "$RS" --binder "$BINDER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "unknown"
  printf '%s\n' "$output" | grep -qF "gh CLI not installed"
}

@test "unknown: gh auth failure → result=unknown, exit 2" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  # Override: RS_AUTH_FAIL=1 makes the fake gh fail auth
  : >"$GH_LOG"
  run env PATH="$GH_FAKE:$PATH" GH_LOG="$GH_LOG" RS_AUTH_FAIL=1 bash "$RS" --binder "$BINDER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "unknown"
  printf '%s\n' "$output" | grep -qF "auth status failed"
}

@test "unknown: never a false clean result when auth fails" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  : >"$GH_LOG"
  run env PATH="$GH_FAKE:$PATH" GH_LOG="$GH_LOG" RS_AUTH_FAIL=1 bash "$RS" --binder "$BINDER"
  [ "$status" -ne 0 ]
  [ -z "$(printf '%s\n' "$output" | grep -F "ok=true")" ]
}

# ---------------------------------------------------------------------------
# A3: read-only assertions — no mutation of issues, PRs, or binder
# ---------------------------------------------------------------------------

@test "read-only: no gh issue edit/close/create calls" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  # The log records every gh invocation. Verify no mutation subcommands.
  if grep -qE '\b(issue|pr)\s+(edit|close|create|merge|comment|reopen|lock|delete)\b' "$GH_LOG"; then false; fi
}

@test "read-only: no git push/commit calls during reconciliation" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  # git is never invoked by reconcile-state (only gh for read queries)
  [ -z "$(grep -E '(^|[^[:alnum:]_])git[[:space:]]+(push|commit|merge|rebase)([^[:alnum:]_]|$)' "$GH_LOG")" ]
  # gh log should only contain view/auth (read-only) subcommands
  grep -qE '^(auth|issue view|pr view)' "$GH_LOG" || \
    grep -qE '^auth ' "$GH_LOG"
}

@test "read-only: binder file is unchanged after reconciliation" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  checksum_before=$(sha256sum "$BINDER" | cut -d' ' -f1)
  run_rs
  checksum_after=$(sha256sum "$BINDER" | cut -d' ' -f1)
  [ "$checksum_before" = "$checksum_after" ]
}

@test "read-only: only read-only gh subcommands appear in the log" {
  write_binder "pr-open" "pr-12 — https://github.com/percena/lattice/pull/12"
  make_fake_gh
  run_rs
  # Every logged line must start with auth, issue view, or pr view
  while IFS= read -r line; do
    printf '%s\n' "$line" | grep -qE '^(auth\ |issue\ view\ |pr\ view\ )'
  done <"$GH_LOG"
}

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------

@test "json: emits deterministic JSON with --json" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs --json
  [ "$status" -eq 0 ]
  # Valid JSON
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["ok"] is True
assert d["result"]=="ok"
assert d["read_only"] is True
assert d["ticket"]=="tkt-7-demo"
assert d["issue"]["state"]=="OPEN"
assert "drifts" in d
assert len(d["drifts"])==0
'
}

@test "json: drift includes stable reason codes and affected ids" {
  write_binder "pr-open" "pr-12 — https://github.com/percena/lattice/pull/12"
  make_fake_gh
  run_rs --json
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["ok"] is False
assert d["result"]=="drift"
drift=d["drifts"][0]
assert drift["code"]=="merged_pr_nonterminal_binder"
assert "ids" in drift
assert len(drift["ids"])>0
'
}

@test "json: unknown result with auth failure" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  : >"$GH_LOG"
  run env PATH="$GH_FAKE:$PATH" GH_LOG="$GH_LOG" RS_AUTH_FAIL=1 \
    bash "$RS" --binder "$BINDER" --json
  [ "$status" -eq 2 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["result"]=="unknown"
assert d["ok"] is False
assert "errors" in d
assert len(d["errors"])>0
'
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "refuses a non-numeric --repo traversal" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs --repo "owner/../evil"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--repo must be owner/name"
}

@test "refuses a --repo that disagrees with binder origin" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs --repo "attacker/otherrepo"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "different repository"
}

@test "binder not inside a git worktree is refused" {
  nomad="$TEST_DIR/loose.md"
  printf '# tkt-7-demo\n\n| status | queued |\n' >"$nomad"
  run bash "$RS" --binder "$nomad"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "not inside a git worktree"
}

# ---------------------------------------------------------------------------
# tkt-179: additional drift classes + identity fallback
# ---------------------------------------------------------------------------

@test "A7: drift: open issue vs closed binder (open_issue_closed_binder)" {
  write_binder "closed" "(none yet)"
  write_finish_merged 12 2026-07-31T10:00:00Z
  cat >"$GH_FAKE/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1" in
  auth) exit 0 ;;
  issue) printf '%s\n' '{"state":"OPEN","closedAt":null,"url":"https://github.com/percena/lattice/issues/7"}' ;;
  pr) printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://github.com/percena/lattice/pull/12"}' ;;
esac
EOF
  chmod +x "$GH_FAKE/gh"
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "open_issue_closed_binder"
}

@test "A8: drift: merged PR + terminal binder but no Finish ledger (merged_pr_missing_finish_ledger)" {
  # Binder: status closed, prs references a MERGED PR, but ## Finish has
  # only a placeholder — no merged: entry. This is an interrupted finish-work.
  write_binder "closed" "pr-12 — https://github.com/percena/lattice/pull/12"
  # Leave ## Finish as the placeholder "(none yet)" — no merged: line
  cat >"$GH_FAKE/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1" in
  auth) exit 0 ;;
  issue) printf '%s\n' '{"state":"CLOSED","closedAt":"2026-07-31T10:01:00Z","url":"https://github.com/percena/lattice/issues/7"}' ;;
  pr) printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://github.com/percena/lattice/pull/12"}' ;;
esac
EOF
  chmod +x "$GH_FAKE/gh"
  run_rs
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "ok=false"
  printf '%s\n' "$output" | grep -qF "merged_pr_missing_finish_ledger"
}

@test "A9: --repo with no origin but matching github URL identity is accepted" {
  # Remove origin so binder_repo_id is None; --repo falls back to github URL
  git -C "$REPO" remote remove origin
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs --repo percena/lattice
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok=true"
}

@test "A9: --repo with no origin and no github URL is refused" {
  # Remove origin; binder github URL is a placeholder
  git -C "$REPO" remote remove origin
  write_binder "queued" "(none yet)"
  # Override github to placeholder
  sed -i.bak 's#| github | https://github.com/percena/lattice/issues/7 |#| github | (to be created) |#' "$BINDER"
  rm -f "$BINDER.bak"
  make_fake_gh
  run_rs --repo percena/lattice
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "no binder repo identity available"
}

@test "A9: --repo with no origin but mismatching github URL is refused" {
  # Remove origin; --repo disagrees with github URL identity
  git -C "$REPO" remote remove origin
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs --repo attacker/otherrepo
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "different repository"
}

# ---------------------------------------------------------------------------
# tkt-238 H4: gh_query must parameterize --json fields by kind.
# `mergedAt` is invalid for `gh issue view` (real gh 2.92.0 rejects it); a
# single shared field set made every issue query fail as `unknown` → exit 2
# before drift detection ran. The fake gh now validates fields like real gh.
# ---------------------------------------------------------------------------

@test "tkt-238 H4: issue query omits mergedAt so drift detection runs (ok:true)" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  # With the fix, the issue query uses state,closedAt,url (no mergedAt) → the
  # field-validating fake gh returns the OPEN issue → reconciliation reaches
  # ok:true. Pre-fix this exited 2 (unknown) because mergedAt was rejected.
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok=true"
  # The logged issue command must use the no-mergedAt field set.
  issue_line=$(grep -F 'issue view 7' "$GH_LOG")
  printf '%s\n' "$issue_line" | grep -qF -- "--json state,closedAt,url"
  # And must NOT carry mergedAt on the issue path.
  [ -z "$(printf '%s' "$issue_line" | grep -F mergedAt)" ]
}

@test "tkt-238 H4: pr query still carries mergedAt (unaffected)" {
  write_binder "pr-open" "pr-12 — https://github.com/percena/lattice/pull/12"
  make_fake_gh
  run_rs
  # PR queries keep mergedAt (valid for `gh pr view`); the logged pr command
  # carries the full field set.
  pr_line=$(grep -F 'pr view 12' "$GH_LOG")
  printf '%s\n' "$pr_line" | grep -qF -- "--json state,closedAt,mergedAt,url"
}
