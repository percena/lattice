#!/usr/bin/env bats
# hermetic end-to-end lifecycle test.
#
# Drives the real lifecycle scripts against a REAL local git repo and a STUBBED
# `gh` (no network). Asserts the four-way contract integrity that unit tests do
# not cover: binder <-> GitHub issue <-> PR <-> Spec coherence at land, plus the
# finish cleanup JSON contract. Also verifies (A4) that breaking a contract edge
# actually fails alignment-check (not a no-op gate).
#
# Scope: single-PR happy path (Fixes primary). Multi-PR / parallel-degree paths
# are a documented follow-up, not this slice.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export REPO_ROOT
  export ENSURE_LATTICE="$REPO_ROOT/skills/_lattice-lib/scripts/ensure-lattice.sh"
  export ENSURE_WS="$REPO_ROOT/skills/_lattice-lib/scripts/ensure-workspace.sh"
  export ALIGN="$REPO_ROOT/skills/finish-work/scripts/alignment-check.sh"
  export CLOSE="$REPO_ROOT/skills/finish-work/scripts/close-fixed-issues.sh"
  export CLEANUP="$REPO_ROOT/skills/finish-work/scripts/cleanup-workspace.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lifecycle-e2e.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$MAIN" "$STUB_BIN"

  # Real local repo standing in for origin's default branch `dev`.
  git -C "$MAIN" init -q -b dev
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

  # gh stub: PR/issue JSON come from files the test writes; graphql/repo are
  # benign. Everything else exits non-zero so unexpected calls surface loudly.
  export GH_PR_JSON="$TEST_DIR/pr.json"
  export GH_ISSUE_JSON="$TEST_DIR/issue.json"
  export GH_ISSUE_STATE_FILE="$TEST_DIR/issue-state"
  export GH_CALL_LOG="$TEST_DIR/gh-calls.log"
  echo OPEN >"$GH_ISSUE_STATE_FILE"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${GH_CALL_LOG:-/dev/null}"
if [[ "$1" == "pr" && "$2" == "view" ]]; then cat "${GH_PR_JSON:?}"; exit 0; fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  # reflect current state so close-fixed-issues sees OPEN then CLOSED
  python3 - "$GH_ISSUE_JSON" "$(cat "$GH_ISSUE_STATE_FILE")" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d["state"]=sys.argv[2]
json.dump(d,sys.stdout)
PY
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "close" ]]; then echo CLOSED >"$GH_ISSUE_STATE_FILE"; exit 0; fi
if [[ "$1" == "issue" && "$2" == "edit" ]]; then exit 0; fi
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  # honor `-q <jq>` the way real gh does, so callers get scalars not blobs
  for a in "$@"; do
    case "$a" in
      *defaultBranchRef.name*) echo "dev"; exit 0 ;;
      *nameWithOwner*) echo "example/repo"; exit 0 ;;
    esac
  done
  printf '{"nameWithOwner":"example/repo","defaultBranchRef":{"name":"dev"}}'; exit 0
fi
if [[ "$1" == "api" ]]; then exit 0; fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  cd "$MAIN"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

write_pr() {
  # $1 body  $2 head branch
  python3 - "$1" "$2" <<'PY' >"$GH_PR_JSON"
import json,sys
json.dump({"number":42,"title":"feat: demo land","body":sys.argv[1],"state":"OPEN",
  "headRefName":sys.argv[2],"baseRefName":"dev","url":"https://example.test/pr/42",
  "isDraft":False,"mergeable":"MERGEABLE"}, sys.stdout)
PY
}

write_issue() {
  # $1 body
  python3 - "$1" <<'PY' >"$GH_ISSUE_JSON"
import json,sys
json.dump({"number":30,"title":"demo ticket","body":sys.argv[1],"state":"OPEN","labels":[]}, sys.stdout)
PY
}

# Simulate the finish-work merge step: rewrite the stub PR JSON to the terminal
# MERGED state with a concrete mergedAt. close-fixed-issues.sh refuses any live
# issue mutation until both PR_STATE=MERGED and MERGED_AT are present, so the
# finish stage must observe a genuinely merged PR before closing Fixes issues.
mark_pr_merged() {
  python3 - "$GH_PR_JSON" <<'PY'
import json,sys,datetime
d=json.load(open(sys.argv[1]))
d["state"]="MERGED"
d["mergedAt"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
json.dump(d,open(sys.argv[1],"w"))
PY
}

# Build the coherent lifecycle state: worktree bound to tkt-30, binder + issue +
# PR all agreeing on Acceptance A1. Sets globals: WT, BINDER, HEAD.
make_coherent_lifecycle() {
  bash "$ENSURE_LATTICE" >/dev/null 2>&1
  local json; json=$(bash "$ENSURE_WS" --mode worktree --bind tkt --id 30 --slug demo 2>/dev/null)
  WT=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])' <<<"$json")
  HEAD="tkt-30-demo"
  export LATTICE_HOME="$WT/.lattice"
  BINDER="$LATTICE_HOME/tickets/tkt-30-demo"
  mkdir -p "$BINDER"
  cat >"$BINDER/README.md" <<'MD'
---
id: tkt-30
kind: feat
status: open
covers: [A1]
prs: [pr-42]
---
## Acceptance
- [x] A1: demo capability implemented
MD
  # issue body Acceptance checked (matches binder)
  write_issue "## Acceptance
- [x] A1: demo capability implemented"
  # PR body Fixes the issue
  write_pr "Why: demo.

Fixes #30" "$HEAD"

  # Commit the binder in the worktree so it is clean before finish cleanup
  # (create-pr commits artifacts in the real lifecycle).
  git -C "$WT" -c user.email=t@t -c user.name=t add .lattice/tickets/tkt-30-demo/README.md
  git -C "$WT" -c user.email=t@t -c user.name=t commit -q -m "binder: tkt-30 demo"
}


@test "harness smoke: coherent lifecycle builds worktree + binder + issue + PR" {
  make_coherent_lifecycle
  [ -d "$WT" ]
  [ -f "$BINDER/README.md" ]
  git -C "$MAIN" show-ref --verify --quiet "refs/heads/$HEAD"
  run bash "$ALIGN" --pr 42
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "A2: alignment asserts binder<->issue<->PR coherence at land (green)" {
  make_coherent_lifecycle
  run bash "$ALIGN" --pr 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok=True"* ]]
  [[ "$output" == *"hard=0"* ]]
  # linkage actually resolved (not a vacuous pass)
  [[ "$output" == *"issues [30]"* ]]
  [[ "$output" == *"binders 1"* ]]
}

@test "A4: breaking the issue<->diff edge fails alignment (not a no-op gate)" {
  make_coherent_lifecycle
  # Regress ONE contract edge: issue Acceptance now unchecked while PR still Fixes it.
  write_issue "## Acceptance
- [ ] A1: demo capability implemented"
  run bash "$ALIGN" --pr 42
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ok=False"* ]]
  [[ "$output" == *"open Acceptance"* ]] || [[ "$output" == *"HARD"* ]]
}

@test "A1/A3: finish stage closes Fixes issue then cleans up (JSON contract)" {
  make_coherent_lifecycle
  # Simulate the merge commit landing on dev so the head tip is an ancestor,
  # then flip the stub PR to MERGED so close-fixed-issues sees merge evidence.
  git -C "$MAIN" merge --no-ff -q -m "merge #42" "$HEAD"
  mark_pr_merged

  # close-fixed-issues: OPEN Fixes #30 -> CLOSED, reported honestly
  run bash "$CLOSE" --pr 42 --expected-closing-ids 30
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status: ok"* ]]
  [ "$(cat "$GH_ISSUE_STATE_FILE")" == "CLOSED" ]

  # cleanup-workspace: worktree + local branch removed; JSON contract present.
  run bash "$CLEANUP" --branch "$HEAD" --keep-remote --worktree-path "$WT"
  echo "$output"
  [ "$status" -eq 0 ]
  json=$(printf '%s\n' "$output" | grep '^{' | tail -1)
  echo "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] is True, d; assert d["removed_worktree"] is True, d; assert d["deleted_local_branch"] is True, d'
  [ ! -d "$WT" ]
  ! git -C "$MAIN" show-ref --verify --quiet "refs/heads/$HEAD"
}
