#!/usr/bin/env bats
# Path-point stamp tests for ensure-workspace.sh (spc-337 A3 / ADR-012 §1,
# tkt-339): a successful `--bind tkt --id N` commits `queued → in-progress`
# through transition-api.py when exactly one queued binder exists under the
# WORKSPACE's Lattice home. Re-bind → no second entry; other statuses are
# untouched; --no-stamp opts out; no binder → no-op; a stamp failure warns
# but the bind still exits 0. The JSON reports `stamped_in_progress`.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export ENSURE="$REPO_ROOT/skills/_lattice-lib/scripts/ensure-workspace.sh"
  export API="$REPO_ROOT/skills/_lattice-lib/scripts/transition-api.py"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ensure-ws-stamp.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  # Out-of-repo state home (ADR-011) so the ledger .lock sidecar never lands
  # in a shared XDG dir keyed by this throwaway repo.
  export LATTICE_STATE_HOME="$TEST_DIR/state"
  mkdir -p "$LATTICE_STATE_HOME"
  export LATTICE_SKIP_FETCH=1
  cd "$MAIN"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# Commit a minimal binder (the field table the real template emits) on main so
# every worktree created from main carries it.
seed_binder() {  # <id> <slug> <status>
  local dir="$MAIN/.lattice/tickets/tkt-$1-$2"
  mkdir -p "$dir"
  cat >"$dir/README.md" <<EOF
# tkt-$1-$2

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| status | $3 |
| fix_cycles | 0 |
| wait_reason | (none) |
| updated | 2026-09-02T00:00:00Z |
| prs | (none) |

## Decision journal

- 2026-09-02 seed
EOF
  git -C "$MAIN" add .lattice
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q -m "seed tkt-$1"
}

binder_status() {  # <binder path>
  grep -m1 -E '^\| status \|' "$1" | awk -F'|' '{ v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v }'
}

@test "worktree bind of a queued binder stamps exactly one queued → in-progress ledger entry in the WORKSPACE home" {
  seed_binder 41 demo queued
  run bash "$ENSURE" --mode worktree --bind tkt --id 41 --slug demo
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": true'
  WT="$TEST_DIR/repo.worktrees/tkt-41-demo"
  [ "$(binder_status "$WT/.lattice/tickets/tkt-41-demo/README.md")" = "in-progress" ]
  LEDGER="$WT/.lattice/.transition-ledger/tkt-41.jsonl"
  [ -f "$LEDGER" ]
  [ "$(wc -l <"$LEDGER" | tr -d ' ')" -eq 1 ]
  grep -qF '"from":"queued","to":"in-progress","owner":"system","reason":"spawn"' "$LEDGER"
  # The main checkout's binder is NOT touched (the workspace is the writer).
  [ "$(binder_status "$MAIN/.lattice/tickets/tkt-41-demo/README.md")" = "queued" ]
  [ ! -e "$MAIN/.lattice/.transition-ledger/tkt-41.jsonl" ]
  # stdout stays a single JSON object (the API's "committed:" line goes to
  # stderr): re-bind a fresh queued binder capturing stdout only.
  seed_binder 40 stdout-only queued
  STDOUT_ONLY="$(bash "$ENSURE" --mode worktree --bind tkt --id 40 --slug stdout-only 2>/dev/null)"
  [ "$(printf '%s\n' "$STDOUT_ONLY" | wc -l | tr -d ' ')" -eq 1 ]
  printf '%s\n' "$STDOUT_ONLY" | grep -qF '"stamped_in_progress": true'
  if printf '%s\n' "$STDOUT_ONLY" | grep -qF 'committed:'; then false; fi
}

@test "re-bind is idempotent: second bind adds no second ledger entry" {
  seed_binder 42 again queued
  run bash "$ENSURE" --mode worktree --bind tkt --id 42 --slug again
  [ "$status" -eq 0 ]
  run bash "$ENSURE" --mode worktree --bind tkt --id 42 --slug again
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"reused_existing_branch": true'
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": false'
  LEDGER="$TEST_DIR/repo.worktrees/tkt-42-again/.lattice/.transition-ledger/tkt-42.jsonl"
  [ "$(wc -l <"$LEDGER" | tr -d ' ')" -eq 1 ]
  [ "$(binder_status "$TEST_DIR/repo.worktrees/tkt-42-again/.lattice/tickets/tkt-42-again/README.md")" = "in-progress" ]
}

@test "a pr-open binder is untouched by bind" {
  seed_binder 43 open pr-open
  run bash "$ENSURE" --mode worktree --bind tkt --id 43 --slug open
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": false'
  WT="$TEST_DIR/repo.worktrees/tkt-43-open"
  [ "$(binder_status "$WT/.lattice/tickets/tkt-43-open/README.md")" = "pr-open" ]
  [ ! -e "$WT/.lattice/.transition-ledger/tkt-43.jsonl" ]
  git -C "$WT" diff --quiet -- .lattice
}

@test "side states (stuck / deferred / rework / parked / closed) are untouched by bind" {
  for pair in "44:stuck" "45:deferred" "46:rework" "47:parked" "48:closed"; do
    id="${pair%%:*}"; st="${pair##*:}"
    seed_binder "$id" "side-$st" "$st"
    run bash "$ENSURE" --mode worktree --bind tkt --id "$id" --slug "side-$st"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qF '"stamped_in_progress": false'
    WT="$TEST_DIR/repo.worktrees/tkt-$id-side-$st"
    [ "$(binder_status "$WT/.lattice/tickets/tkt-$id-side-$st/README.md")" = "$st" ]
    [ ! -e "$WT/.lattice/.transition-ledger/tkt-$id.jsonl" ]
  done
}

@test "--no-stamp skips the stamp and leaves the queued binder alone" {
  seed_binder 49 skip queued
  run bash "$ENSURE" --mode worktree --bind tkt --id 49 --slug skip --no-stamp
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": false'
  WT="$TEST_DIR/repo.worktrees/tkt-49-skip"
  [ "$(binder_status "$WT/.lattice/tickets/tkt-49-skip/README.md")" = "queued" ]
  [ ! -e "$WT/.lattice/.transition-ledger/tkt-49.jsonl" ]
}

@test "no binder → no-op with stamped_in_progress false (exit 0, JSON intact)" {
  run bash "$ENSURE" --mode worktree --bind tkt --id 50 --slug nobinder
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": false'
  printf '%s\n' "$output" | grep -qF '"ok": true'
  [ ! -d "$TEST_DIR/repo.worktrees/tkt-50-nobinder/.lattice/.transition-ledger" ]
}

@test "binder lookup matches the id segment exactly (tkt-5- does not match tkt-51-)" {
  seed_binder 51 other queued
  run bash "$ENSURE" --mode worktree --bind tkt --id 5 --slug exact
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": false'
  [ "$(binder_status "$TEST_DIR/repo.worktrees/tkt-5-exact/.lattice/tickets/tkt-51-other/README.md")" = "queued" ]
}

@test "branch mode bind also stamps (workspace = the checkout itself)" {
  seed_binder 52 branchy queued
  run bash "$ENSURE" --mode branch --bind tkt --id 52 --slug branchy
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": true'
  [ "$(binder_status "$MAIN/.lattice/tickets/tkt-52-branchy/README.md")" = "in-progress" ]
  [ "$(wc -l <"$MAIN/.lattice/.transition-ledger/tkt-52.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "stamp failure warns on stderr but the bind still exits 0 with stamped_in_progress false" {
  seed_binder 53 broken queued
  # Break the API for this run only: a python3 shim that fails when asked to
  # run transition-api.py and otherwise defers to the real interpreter.
  REAL_PY="$(command -v python3)"
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/python3" <<EOF
#!/usr/bin/env bash
case "\$1" in
  */transition-api.py) echo "simulated transition failure" >&2; exit 3 ;;
esac
exec "$REAL_PY" "\$@"
EOF
  chmod +x "$TEST_DIR/bin/python3"
  run env PATH="$TEST_DIR/bin:$PATH" bash "$ENSURE" --mode worktree --bind tkt --id 53 --slug broken
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'stamp FAILED for tkt-53'
  printf '%s\n' "$output" | grep -qF 'commit tkt-53 in-progress system spawn --binder'
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": false'
  printf '%s\n' "$output" | grep -qF '"ok": true'
  [ "$(binder_status "$TEST_DIR/repo.worktrees/tkt-53-broken/.lattice/tickets/tkt-53-broken/README.md")" = "queued" ]
}

@test "stamp lands in an explicit LATTICE_HOME when the caller pins one" {
  seed_binder 54 pinned queued
  CUSTOM="$TEST_DIR/custom-lattice"
  mkdir -p "$CUSTOM/tickets/tkt-54-pinned"
  cp "$MAIN/.lattice/tickets/tkt-54-pinned/README.md" "$CUSTOM/tickets/tkt-54-pinned/README.md"
  run env LATTICE_HOME="$CUSTOM" bash "$ENSURE" --mode worktree --bind tkt --id 54 --slug pinned
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"stamped_in_progress": true'
  [ "$(binder_status "$CUSTOM/tickets/tkt-54-pinned/README.md")" = "in-progress" ]
  [ -f "$CUSTOM/.transition-ledger/tkt-54.jsonl" ]
  # The worktree copy (not the pinned home) stays queued.
  [ "$(binder_status "$TEST_DIR/repo.worktrees/tkt-54-pinned/.lattice/tickets/tkt-54-pinned/README.md")" = "queued" ]
}
