#!/usr/bin/env bats
# Tests for finish-commit.sh: commit the staged Lattice finish set and assert
# the post-commit index is clean under .lattice (tkt-360 A2/A3).
#
# finish-ledger.sh stages the binder + ledger; finish-commit.sh commits that
# staged set and fails closed when the post-commit .lattice index is dirty
# (stranded staged/unstaged changes from an interrupted loop, a held index lock,
# or a ledger silently dropped by `git add`).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export FC="$REPO_ROOT/skills/_lattice-lib/scripts/finish-commit.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fc.XXXXXX")"
  REPO="$TEST_DIR/repo"
  export LATTICE_HOME="$REPO/.lattice"
  BINDER_DIR="$REPO/.lattice/tickets/tkt-7-demo"
  mkdir -p "$BINDER_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  BINDER="$BINDER_DIR/README.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Minimal binder + ledger pair already staged, mimicking finish-ledger's output.
stage_finish_set() {
  # base commit has the binder in its pre-stamp state (no ledger yet — finish-ledger
  # creates the ledger fresh), so the finish commit actually shows the ledger as
  # a new file (matching the real finish-ledger → finish-commit flow).
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| Field | Value |
| --- | --- |
| status | pr-open |
| prs | (none yet) |

## Finish

- (none yet)
MD
  git -C "$REPO" add -A >/dev/null 2>&1
  git -C "$REPO" commit -qm base >/dev/null 2>&1 || true
  # simulate finish-ledger: flip binder to closed + append the ledger entry,
  # then stage both (finish-ledger stages binder README + .transition-ledger).
  cat >"$BINDER" <<'MD'
# tkt-7-demo

| Field | Value |
| --- | --- |
| status | closed |
| prs | pr-12 — https://github.com/percena/lattice/pull/12 |

## Finish

- pr-12 merged: 2026-07-31T10:00:00Z — https://github.com/percena/lattice/pull/12 (base merge)
MD
  mkdir -p "$REPO/.lattice/.transition-ledger"
  printf '{"ts":"2026-07-31T10:00:00Z","ticket":"tkt-7","from":"pr-open","to":"closed","reason":"merge","metric":"merge-count"}\n' \
    > "$REPO/.lattice/.transition-ledger/tkt-7.jsonl"
  git -C "$REPO" add -- "$BINDER" "$REPO/.lattice/.transition-ledger/tkt-7.jsonl" >/dev/null 2>&1
}

@test "happy path: commits staged binder + ledger, asserts index clean" {
  stage_finish_set
  run bash "$FC" --message "finish(tkt-7): stamp Finish ledger — pr-12 merged, #7 closed" --repo "$REPO"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "finish-commit: committed"
  # the ledger is in the commit (not stranded)
  git -C "$REPO" show --stat HEAD | grep -q '.transition-ledger/tkt-7.jsonl'
  # post-commit .lattice is clean
  [ -z "$(git -C "$REPO" status --porcelain -- .lattice)" ]
}

@test "tkt-367: no --repo (empty GIT_DIR_ARGS) resolves root from cwd (bash-3.2 safe)" {
  # The dogfood scenario: finish-commit.sh --message "..." with no --repo, so
  # GIT_DIR_ARGS stays empty. Under `set -u` on bash 3.2, a bare
  # `${GIT_DIR_ARGS[@]}` triggers "unbound variable" — the + guard (tkt-367)
  # must keep this path working. Run under /bin/bash when it is bash 3.2 to
  # exercise the actual regression platform; else the bats bash (4+).
  stage_finish_set
  RUN_BASH="bash"
  if [ "$(/bin/bash --version 2>/dev/null | grep -o 'version [0-9]\+\.[0-9]\+' | head -1)" = "version 3.2" ]; then
    RUN_BASH="/bin/bash"
  fi
  # cwd is the repo root so `git rev-parse --show-toplevel` resolves without -C.
  run bash -c "cd '$REPO' && '$RUN_BASH' '$FC' --message 'finish(tkt-7): no --repo'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "finish-commit: committed"
  [ -z "$(git -C "$REPO" status --porcelain -- .lattice)" ]
  # must NOT emit the unbound-variable error on bash 3.2
  if printf '%s\n' "$output" | grep -q 'unbound variable'; then false; fi
}

@test "nothing staged: exits 0 with a skip note (finish-ledger no-binder path)" {
  git -C "$REPO" commit -qm base --allow-empty >/dev/null 2>&1 || true
  run bash "$FC" --message "finish(tkt-7): nothing" --repo "$REPO"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "nothing staged"
}

@test "missing --message is rejected" {
  run bash "$FC" --repo "$REPO"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "Error: --message is required"
}

@test "dirty post-commit index (stranded unstaged .lattice change) fails closed" {
  stage_finish_set
  # simulate an interrupted loop: a second binder modified but NOT staged
  mkdir -p "$REPO/.lattice/tickets/tkt-8-demo"
  printf '# tkt-8\n## stranded\n' > "$REPO/.lattice/tickets/tkt-8-demo/README.md"
  run bash "$FC" --message "finish(tkt-7): stamp Finish ledger — pr-12 merged, #7 closed" --repo "$REPO"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "post-commit index is NOT clean"
  printf '%s\n' "$output" | grep -qF "tkt-360 A2"
  printf '%s\n' "$output" | grep -qF "recovery:"
  # the commit DID land (the dirty tree is the symptom, not a lost commit)
  git -C "$REPO" show --stat HEAD | grep -q '.transition-ledger/tkt-7.jsonl'
}

@test "commit failure (unwritable index) fails closed" {
  stage_finish_set
  # Point GIT_INDEX_FILE at a path whose parent does not exist — git cannot
  # create the index file, so `git commit` fails (simulates a held/corrupted
  # index lock without leaving a real .lock artifact behind).
  run env GIT_INDEX_FILE="$TEST_DIR/no/such/dir/index" bash "$FC" \
    --message "finish(tkt-7): stamp Finish ledger — pr-12 merged, #7 closed" --repo "$REPO"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "git commit failed"
}
