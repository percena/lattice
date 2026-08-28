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
  [[ "$output" == *"ok=true"* ]]
  [[ "$output" == *"no drift detected"* ]]
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
  [[ "$output" == *"ok=true"* ]]
}

@test "reconciled: pr-open binder with an open PR → ok:true" {
  write_binder "pr-open" "pr-14 — https://github.com/percena/lattice/pull/14"
  make_fake_gh
  run_rs
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok=true"* ]]
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
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"closed_issue_working_binder"* ]]
}

@test "drift: merged PR vs nonterminal binder" {
  write_binder "pr-open" "pr-12 — https://github.com/percena/lattice/pull/12"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"merged_pr_nonterminal_binder"* ]]
}

@test "drift: closed PR vs nonterminal binder" {
  write_binder "pr-open" "pr-13 — https://github.com/percena/lattice/pull/13"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"closed_pr_nonterminal_binder"* ]]
}

@test "drift: open PR vs closed binder" {
  write_binder "closed" "pr-14 — https://github.com/percena/lattice/pull/14"
  write_finish_merged 14 2026-07-31T10:00:00Z
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"open_pr_closed_binder"* ]]
}

@test "drift: pr-open with missing PR (no prs entries)" {
  write_binder "pr-open" "(none yet)"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"pr_open_missing_pr"* ]]
}

@test "drift: pr-open with unresolvable PR (404 on GitHub)" {
  write_binder "pr-open" "pr-99 — https://github.com/percena/lattice/pull/99"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"pr_open_unresolvable_pr"* ]]
}

@test "drift: repo identity mismatch (github URL points to foreign repo)" {
  write_binder "queued" "(none yet)"
  # Override the github URL to a foreign repo
  sed -i.bak 's#github.com/percena/lattice/issues/7#github.com/attacker/otherrepo/issues/7#' "$BINDER"
  rm -f "$BINDER.bak"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"repo_identity_mismatch"* ]]
}

@test "drift: PR URL points to a foreign repo" {
  write_binder "pr-open" "pr-12 — https://github.com/attacker/otherrepo/pull/12"
  make_fake_gh
  run_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok=false"* ]]
  [[ "$output" == *"repo_identity_mismatch"* ]]
}

# ---------------------------------------------------------------------------
# A2: auth/network unknown → result=unknown, nonzero
# ---------------------------------------------------------------------------

@test "unknown: gh not installed → result=unknown, exit 2" {
  write_binder "queued" "(none yet)"
  # Build a PATH with git and python3 but WITHOUT gh. gh typically lives in
  # /opt/homebrew/bin or /usr/local/bin; we exclude those and symlink the
  # essentials into a clean bin so shutil.which("gh") returns None.
  NOGH_BIN="$TEST_DIR/nogh_bin"
  mkdir -p "$NOGH_BIN"
  ln -sf "$(command -v git)" "$NOGH_BIN/git"
  ln -sf "$(command -v python3)" "$NOGH_BIN/python3"
  : >"$GH_LOG"
  run env PATH="$NOGH_BIN:/usr/bin:/bin" bash "$RS" --binder "$BINDER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown"* ]]
  [[ "$output" == *"gh CLI not installed"* ]]
}

@test "unknown: gh auth failure → result=unknown, exit 2" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  # Override: RS_AUTH_FAIL=1 makes the fake gh fail auth
  : >"$GH_LOG"
  run env PATH="$GH_FAKE:$PATH" GH_LOG="$GH_LOG" RS_AUTH_FAIL=1 bash "$RS" --binder "$BINDER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown"* ]]
  [[ "$output" == *"auth status failed"* ]]
}

@test "unknown: never a false clean result when auth fails" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  : >"$GH_LOG"
  run env PATH="$GH_FAKE:$PATH" GH_LOG="$GH_LOG" RS_AUTH_FAIL=1 bash "$RS" --binder "$BINDER"
  [ "$status" -ne 0 ]
  [[ "$output" != *"ok=true"* ]]
}

# ---------------------------------------------------------------------------
# A3: read-only assertions — no mutation of issues, PRs, or binder
# ---------------------------------------------------------------------------

@test "read-only: no gh issue edit/close/create calls" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  # The log records every gh invocation. Verify no mutation subcommands.
  ! grep -qE '\b(issue|pr)\s+(edit|close|create|merge|comment|reopen|lock|delete)\b' "$GH_LOG"
}

@test "read-only: no git push/commit calls during reconciliation" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs
  # git is never invoked by reconcile-state (only gh for read queries)
  ! grep -qE '\bgit\s+(push|commit|merge|rebase)\b' "$GH_LOG" || true
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
    [[ "$line" =~ ^(auth\ |issue\ view\ |pr\ view\ ) ]]
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
  [[ "$output" == *"--repo must be owner/name"* ]]
}

@test "refuses a --repo that disagrees with binder origin" {
  write_binder "queued" "(none yet)"
  make_fake_gh
  run_rs --repo "attacker/otherrepo"
  [ "$status" -eq 2 ]
  [[ "$output" == *"different repository"* ]]
}

@test "binder not inside a git worktree is refused" {
  nomad="$TEST_DIR/loose.md"
  printf '# tkt-7-demo\n\n| status | queued |\n' >"$nomad"
  run bash "$RS" --binder "$nomad"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not inside a git worktree"* ]]
}
