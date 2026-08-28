#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  UPDATE="$SCRIPT_DIR/update-pr-base.sh"
  ALIGN="$SCRIPT_DIR/alignment-check.sh"
}

setup_gh_stub() {
  TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/update-pr.XXXXXX")}"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export GH_VIEW_COUNT_FILE="$TEST_DIR/gh-view-count"
  export GH_UPDATE_CALLED_FILE="$TEST_DIR/gh-update-called"
  export GH_UPDATE_ARGS_FILE="$TEST_DIR/gh-update-args"
  export GH_REPO_JSON='{"nameWithOwner":"example/repo","defaultBranchRef":{"name":"dev"}}'
  export GH_ORIGIN_REPO_JSON='{"nameWithOwner":"example/repo"}'
  export GH_PUSH_REPO_JSON='{"nameWithOwner":"example/repo"}'
  export GH_INITIAL_JSON='{"id":"PR_test","number":1,"url":"https://example.test/pr/1","state":"OPEN","title":"t","headRefName":"feat-x","headRefOid":"1111111111111111111111111111111111111111","headRepository":{"nameWithOwner":"example/repo"},"isCrossRepository":false,"baseRefName":"dev","baseRefOid":"2222222222222222222222222222222222222222","mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","isDraft":false}'
  export GH_POST_JSON='{"headRefOid":"3333333333333333333333333333333333333333","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}'
  export GH_UPDATE_RC=0
  export GH_UPDATE_OUTPUT="updated"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  if [[ "$3" == "--json" ]]; then
    printf '%s' "$GH_REPO_JSON"
  elif [[ "$3" == *"push-target"* ]]; then
    printf '%s' "$GH_PUSH_REPO_JSON"
  else
    printf '%s' "$GH_ORIGIN_REPO_JSON"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  count=0
  if [[ -f "$GH_VIEW_COUNT_FILE" ]]; then count=$(cat "$GH_VIEW_COUNT_FILE"); fi
  count=$((count + 1))
  printf '%s' "$count" >"$GH_VIEW_COUNT_FILE"
  if [[ "$count" -eq 1 ]]; then
    printf '%s' "$GH_INITIAL_JSON"
  else
    printf '%s' "$GH_POST_JSON"
  fi
  exit 0
fi
if [[ "$1" == "api" && "$2" == "graphql" ]]; then
  : >"$GH_UPDATE_CALLED_FILE"
  printf '%q ' "$@" >"$GH_UPDATE_ARGS_FILE"
  printf '%s' "$GH_UPDATE_OUTPUT"
  exit "$GH_UPDATE_RC"
fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
}

@test "update-pr-base requires --pr" {
  run bash "$UPDATE"
  [ "$status" -eq 2 ]
}

@test "alignment-check requires --pr" {
  run bash "$ALIGN"
  [ "$status" -eq 2 ]
}

@test "update-pr-base --help" {
  run bash "$UPDATE" --help
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "Usage"
}

@test "alignment-check --help" {
  run bash "$ALIGN" --help
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "Usage"
}

# --- --rebase path against a real origin (stubbed gh, no network) ---

setup_rebase_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/update-pr.XXXXXX")"
  ORIGIN="$TEST_DIR/origin.git"
  SEED="$TEST_DIR/seed"
  LOCAL="$TEST_DIR/local"
  git init -q --bare -b main "$ORIGIN"

  git clone -q "$ORIGIN" "$SEED" 2>/dev/null
  git -C "$SEED" config user.email lattice-test@example.invalid
  git -C "$SEED" config user.name 'Lattice Test'
  git -C "$SEED" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$SEED" push -q origin main
  git -C "$SEED" checkout -q -b feat-x
  git -C "$SEED" -c user.email=t@t -c user.name=t commit -q --allow-empty -m feat-1
  git -C "$SEED" push -q origin feat-x

  # local clone holds feat-x at feat-1
  git clone -q "$ORIGIN" "$LOCAL" 2>/dev/null
  git -C "$LOCAL" config user.email lattice-test@example.invalid
  git -C "$LOCAL" config user.name 'Lattice Test'
  git -C "$LOCAL" checkout -q feat-x

  # remote moves ahead: extra commit on feat-x, and base advances
  git -C "$SEED" -c user.email=t@t -c user.name=t commit -q --allow-empty -m remote-only
  git -C "$SEED" push -q origin feat-x
  git -C "$SEED" checkout -q main
  git -C "$SEED" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base-advance
  git -C "$SEED" push -q origin main

  setup_gh_stub
  head_oid=$(git -C "$SEED" rev-parse feat-x)
  base_oid=$(git -C "$SEED" rev-parse main)
  export GH_REPO_JSON='{"nameWithOwner":"example/repo","defaultBranchRef":{"name":"main"}}'
  export GH_INITIAL_JSON="{\"id\":\"PR_test\",\"number\":1,\"url\":\"https://example.test/pr/1\",\"state\":\"OPEN\",\"title\":\"t\",\"headRefName\":\"feat-x\",\"headRefOid\":\"$head_oid\",\"headRepository\":{\"nameWithOwner\":\"example/repo\"},\"isCrossRepository\":false,\"baseRefName\":\"main\",\"baseRefOid\":\"$base_oid\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"BEHIND\",\"isDraft\":false}"
  export GH_POST_JSON="{\"headRefOid\":\"$head_oid\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\"}"
}

teardown() {
  cd /
  if [[ -n "${TEST_DIR:-}" ]]; then rm -rf "$TEST_DIR"; fi
}

@test "rebase fast-forwards a stale local branch instead of dropping remote-only commits" {
  setup_rebase_fixture
  cd "$LOCAL"
  run bash "$UPDATE" --pr 1 --rebase
  [ "$status" -eq 0 ]
  git fetch -q origin
  # remote-only survived the force-with-lease push and sits on top of the new base
  git -C "$LOCAL" log origin/feat-x --format=%s | grep -qx "remote-only"
  base_tip=$(git -C "$LOCAL" rev-parse origin/main)
  git -C "$LOCAL" merge-base --is-ancestor "$base_tip" origin/feat-x
}

@test "rebase refuses a diverged local branch (no forced push)" {
  setup_rebase_fixture
  git -C "$LOCAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m local-only
  before=$(git -C "$SEED" ls-remote origin feat-x | cut -f1)
  cd "$LOCAL"
  run bash "$UPDATE" --pr 1 --rebase
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "stale_local_diverged"
  after=$(git -C "$SEED" ls-remote origin feat-x | cut -f1)
  # remote tip unchanged: remote-only commit still present
  [ "$after" = "$before" ]
  git -C "$SEED" log "$after" --format=%s | grep -qx "remote-only"
}

@test "rebase rejects the live default branch even when it is dev" {
  setup_gh_stub
  export GH_INITIAL_JSON='{"id":"PR_test","number":1,"url":"https://example.test/pr/1","state":"OPEN","title":"t","headRefName":"dev","headRefOid":"1111111111111111111111111111111111111111","headRepository":{"nameWithOwner":"example/repo"},"isCrossRepository":false,"baseRefName":"release","baseRefOid":"2222222222222222222222222222222222222222","mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","isDraft":false}'
  run bash "$UPDATE" --pr 1 --rebase --dry-run
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "head_is_default"'
}

@test "rebase rejects non-default long-lived head main when default is dev" {
  setup_gh_stub
  export GH_REPO_JSON='{"nameWithOwner":"example/repo","defaultBranchRef":{"name":"dev"}}'
  export GH_INITIAL_JSON='{"id":"PR_test","number":1,"url":"https://example.test/pr/1","state":"OPEN","title":"t","headRefName":"main","headRefOid":"1111111111111111111111111111111111111111","headRepository":{"nameWithOwner":"example/repo"},"isCrossRepository":false,"baseRefName":"dev","baseRefOid":"2222222222222222222222222222222222222222","mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","isDraft":false}'
  run bash "$UPDATE" --pr 1 --rebase --dry-run
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "head_is_long_lived"'
  printf '%s\n' "$output" | grep -qF '"head": "main"'
}

@test "rebase rejects conventional long-lived head release when default is dev" {
  setup_gh_stub
  export GH_REPO_JSON='{"nameWithOwner":"example/repo","defaultBranchRef":{"name":"dev"}}'
  export GH_INITIAL_JSON='{"id":"PR_test","number":1,"url":"https://example.test/pr/1","state":"OPEN","title":"t","headRefName":"release","headRefOid":"1111111111111111111111111111111111111111","headRepository":{"nameWithOwner":"example/repo"},"isCrossRepository":false,"baseRefName":"dev","baseRefOid":"2222222222222222222222222222222222222222","mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","isDraft":false}'
  run bash "$UPDATE" --pr 1 --rebase --dry-run
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "head_is_long_lived"'
  printf '%s\n' "$output" | grep -qF '"head": "release"'
}

@test "rebase rejects a fork head even when its short branch name exists upstream" {
  setup_gh_stub
  export GH_INITIAL_JSON='{"id":"PR_test","number":1,"url":"https://example.test/pr/1","state":"OPEN","title":"t","headRefName":"feat-x","headRefOid":"1111111111111111111111111111111111111111","headRepository":{"nameWithOwner":"contributor/repo"},"isCrossRepository":true,"baseRefName":"dev","baseRefOid":"2222222222222222222222222222222222222222","mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","isDraft":false}'
  run bash "$UPDATE" --pr 1 --rebase --dry-run
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "fork_head"'
  printf '%s\n' "$output" | grep -qF 'contributor/repo'
}

@test "rebase rejects when git origin is not the GitHub repository being reviewed" {
  setup_rebase_fixture
  export GH_ORIGIN_REPO_JSON='{"nameWithOwner":"someone-else/repo"}'
  cd "$LOCAL"
  run bash "$UPDATE" --pr 1 --rebase --dry-run
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "origin_repository_mismatch"'
  printf '%s\n' "$output" | grep -qF 'someone-else/repo'
}

@test "rebase rejects when origin pushurl targets a different repository" {
  setup_rebase_fixture
  git -C "$LOCAL" remote set-url --push origin git@github.com:push-target/repo.git
  export GH_PUSH_REPO_JSON='{"nameWithOwner":"push-target/repo"}'
  cd "$LOCAL"
  run bash "$UPDATE" --pr 1 --rebase --dry-run
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "origin_repository_mismatch"'
  printf '%s\n' "$output" | grep -qF '"originPushRepository": "push-target/repo"'
}

@test "rebase refuses when fetched head no longer matches the PR head OID" {
  setup_rebase_fixture
  export GH_INITIAL_JSON="${GH_INITIAL_JSON/\"headRefOid\":\"/\"headRefOid\":\"0000000000000000000000000000000000000000}"
  cd "$LOCAL"
  run bash "$UPDATE" --pr 1 --rebase
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "head_oid_changed"'
}

@test "update-branch permission errors are never accepted as noop" {
  setup_gh_stub
  export GH_UPDATE_RC=1
  export GH_UPDATE_OUTPUT="GraphQL: Cannot update branch: update branch permission denied"
  run bash "$UPDATE" --pr 1
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "update_failed"'
  [ -z "$(printf '%s\n' "$output" | grep -F '"ok": true')" ]
}

@test "update-branch fails when refreshed state remains behind" {
  setup_gh_stub
  export GH_POST_JSON='{"headRefOid":"3333333333333333333333333333333333333333","mergeable":"MERGEABLE","mergeStateStatus":"BEHIND"}'
  run bash "$UPDATE" --pr 1
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "behind_after_update"'
}

@test "already up-to-date state is a verified noop without calling update-branch" {
  setup_gh_stub
  export GH_INITIAL_JSON='{"id":"PR_test","number":1,"url":"https://example.test/pr/1","state":"OPEN","title":"t","headRefName":"feat-x","headRefOid":"1111111111111111111111111111111111111111","headRepository":{"nameWithOwner":"example/repo"},"isCrossRepository":false,"baseRefName":"dev","baseRefOid":"2222222222222222222222222222222222222222","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","isDraft":false}'
  run bash "$UPDATE" --pr 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"action": "noop"'
  [ ! -e "$GH_UPDATE_CALLED_FILE" ]
}

@test "update-branch succeeds only after refreshed state is up to date" {
  setup_gh_stub
  run bash "$UPDATE" --pr 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"action": "update_branch"'
  printf '%s\n' "$output" | grep -qF '"mergeStateStatus": "CLEAN"'
  [ -e "$GH_UPDATE_CALLED_FILE" ]
  grep -q 'pullRequestId=PR_test' "$GH_UPDATE_ARGS_FILE"
  grep -q 'expectedHeadOid=1111111111111111111111111111111111111111' "$GH_UPDATE_ARGS_FILE"
}

@test "unknown initial mergeability fails closed" {
  setup_gh_stub
  export GH_INITIAL_JSON='{"id":"PR_test","number":1,"url":"https://example.test/pr/1","state":"OPEN","title":"t","headRefName":"feat-x","headRefOid":"1111111111111111111111111111111111111111","headRepository":{"nameWithOwner":"example/repo"},"isCrossRepository":false,"baseRefName":"dev","baseRefOid":"2222222222222222222222222222222222222222","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN","isDraft":false}'
  run bash "$UPDATE" --pr 1
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "unverified_initial_mergeable"'
  [ ! -e "$GH_UPDATE_CALLED_FILE" ]
}

@test "unknown refreshed mergeability fails closed" {
  setup_gh_stub
  export GH_POST_JSON='{"headRefOid":"3333333333333333333333333333333333333333","mergeable":"UNKNOWN","mergeStateStatus":"CLEAN"}'
  run bash "$UPDATE" --pr 1
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"reason": "unverified_mergeable_after_update"'
}

# --- interruption during rebase (real signal, not a simulated one) ---

# Wrap git so `rebase` blocks long enough to be signalled, and so every push is
# recorded. The wrapper must not swallow the signal: the script under test is
# the one that has to react.
install_slow_rebase_git() {
  local real_git; real_git=$(command -v git)
  cat >"$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "push" ]]; then printf '%s\n' "\$*" >>"$TEST_DIR/push.log"; fi
done
for a in "\$@"; do
  if [[ "\$a" == "rebase" ]]; then
    # a real rebase would run here; hold the process instead so the test can
    # deliver a signal at exactly this point
    printf 'started\n' >"$TEST_DIR/rebase-started"
    sleep 10
    exit 0
  fi
done
exec "$real_git" "\$@"
EOF
  chmod +x "$STUB_BIN/git"
}

@test "SIGTERM during rebase restores the checkout and never pushes" {
  setup_rebase_fixture
  install_slow_rebase_git
  cd "$LOCAL"
  # detach the head branch from any worktree so the fallback checkout path runs
  git -C "$LOCAL" checkout -q main
  before_branch=$(git -C "$LOCAL" branch --show-current)

  PATH="$STUB_BIN:$PATH" bash "$UPDATE" --pr 1 --rebase >"$TEST_DIR/out" 2>"$TEST_DIR/err" &
  script_pid=$!

  waited=0
  while [[ ! -f "$TEST_DIR/rebase-started" && $waited -lt 100 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  [ -f "$TEST_DIR/rebase-started" ]

  kill -TERM "$script_pid" 2>/dev/null || true
  wait "$script_pid" || script_status=$?
  [ "${script_status:-0}" -ne 0 ]

  # the operator is back on their branch, not parked on the PR head
  [ "$(git -C "$LOCAL" branch --show-current)" = "$before_branch" ]
  # and nothing was published
  [ ! -s "$TEST_DIR/push.log" ]
  grep -q "aborting base update before any push" "$TEST_DIR/err"
}
