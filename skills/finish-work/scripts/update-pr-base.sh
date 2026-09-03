#!/usr/bin/env bash
# Update a GitHub PR head onto its base when behind (finish-work preflight).
#
# Usage:
#   update-pr-base.sh --pr <N> [--rebase] [--allow-local-ahead] [--dry-run]
#
# Default: GitHub updatePullRequestBranch mutation with expectedHeadOid
#          (merge base tip into head; no history rewrite).
# --rebase: local git fetch + rebase onto origin/<base> + force-with-lease push
#           of the feature branch only (never default branch). Runs inside the
#           worktree that checks out the head when one exists; a local branch
#           AHEAD of origin/<head> is refused unless --allow-local-ahead.
#
# stdout: JSON summary. On success it includes:
#   diff_changed — true when the update changed the PR's effective diff
#                  (git diff base...HEAD content) vs before the update;
#                  false on noop or a clean, content-identical update.
#                  Probe failure degrades to true (conservative: unknown
#                  diff must void any prior review verdict).
#   conflict     — true when the merge/rebase hit conflicts (also set on
#                  the conflict-shaped failure JSONs); always false on
#                  success, since a conflicted update never completes here.
# exit 0 = ready (or already up to date)
# exit 1 = conflict / not mergeable after attempt / error (message on stderr + JSON)
# exit 2 = usage
set -euo pipefail

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
bash "$(dirname "${BASH_SOURCE[0]}")/../../_lattice-lib/scripts/ensure-python3.sh" || exit 1

PR=""
REBASE=false
DRY_RUN=false
ALLOW_LOCAL_AHEAD=false

usage() {
  cat >&2 <<'EOF'
Usage: update-pr-base.sh --pr <N> [--rebase] [--allow-local-ahead] [--dry-run]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:-}"; shift 2 ;;
    --rebase) REBASE=true; shift ;;
    --allow-local-ahead) ALLOW_LOCAL_AHEAD=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ -z "$PR" || ! "$PR" =~ ^[1-9][0-9]*$ ]]; then
  usage
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh is required" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required" >&2
  exit 1
fi

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

# baseRefOid is absent from gh pr view --json on older gh (≤ 2.45.x — tkt-293);
# the base commit SHA is fetched separately via REST below. stderr is captured
# to a temp file so a field/contract mismatch or auth failure is diagnosable
# without leaking gh deprecation/rate-limit noise on success (tkt-311 A3).
_view_err=$(mktemp)
view_json=$(gh pr view "$PR" --json id,number,url,state,title,headRefName,headRefOid,headRepository,isCrossRepository,baseRefName,mergeable,mergeStateStatus,isDraft 2>"$_view_err") || {
  cat "$_view_err" >&2
  echo "Error: cannot view PR #$PR (gh pr view failed — see diagnostic above)" >&2
  rm -f "$_view_err"
  exit 1
}
rm -f "$_view_err"

repo_json=$(gh repo view --json nameWithOwner,defaultBranchRef 2>/dev/null) || {
  echo "Error: cannot resolve current GitHub repository identity" >&2
  exit 1
}

# One structured parse for PR identity + one for repository identity.
_parsed=$(python3 -c '
import json, sys
view = json.loads(sys.argv[1])
repo = json.loads(sys.argv[2])

def val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v) if v is not None else ""

print(val(view.get("headRefName") or ""))
print(val(view.get("id") or ""))
print(val(view.get("headRefOid") or ""))
print(val((view.get("headRepository") or {}).get("nameWithOwner") or ""))
print(val(bool(view.get("isCrossRepository"))))
print(val(view.get("baseRefName") or ""))
print(val(view.get("mergeable") or ""))
print(val(view.get("mergeStateStatus") or ""))
print(val(view.get("state") or ""))
print(val(bool(view.get("isDraft"))))
print(val(view.get("url") or ""))
print(val(repo.get("nameWithOwner") or ""))
print(val((repo.get("defaultBranchRef") or {}).get("name") or ""))
' "$view_json" "$repo_json")
{ IFS= read -r HEAD_BRANCH
  IFS= read -r PR_NODE_ID
  IFS= read -r HEAD_OID
  IFS= read -r HEAD_REPOSITORY
  IFS= read -r IS_CROSS_REPOSITORY
  IFS= read -r BASE_BRANCH
  IFS= read -r MERGEABLE
  IFS= read -r MERGE_STATE_INITIAL
  IFS= read -r STATE
  IFS= read -r IS_DRAFT
  IFS= read -r URL
  IFS= read -r REPOSITORY
  IFS= read -r DEFAULT_BRANCH
} <<< "$_parsed"

# Extract hostname from the PR URL for the --hostname flag on gh api (tkt-325,
# mirrors the #311 fix in alignment-check.sh / close-fixed-issues.sh /
# finish-ledger.sh). gh pr view / gh repo view resolve the host from the git
# remote; gh api does NOT — it defaults to github.com, 404ing on GHE.
API_HOST=""
if [[ "$URL" =~ ^https?://([^/]+)/ ]]; then
  API_HOST="${BASH_REMATCH[1]}"
fi

# Fetch both base branch name and base commit SHA from a single REST call so
# the (branch, sha) pair is an atomic snapshot — no TOCTOU window between
# gh pr view and a separate base.sha fetch (tkt-311 A2). stderr captured to
# temp file, emitted only on failure (tkt-311 A3 — same pattern as gh pr view).
_base_err=$(mktemp)
base_json=$(gh api "repos/${REPOSITORY}/pulls/${PR}" ${API_HOST:+--hostname "$API_HOST"} --jq '.base' 2>"$_base_err") || {
  cat "$_base_err" >&2
  echo "Error: cannot fetch base identity for PR #$PR via REST (repos/${REPOSITORY}/pulls/${PR}) — see diagnostic above" >&2
  rm -f "$_base_err"
  exit 1
}
rm -f "$_base_err"
_parsed=$(printf '%s' "$base_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("ref") or "")
print(d.get("sha") or "")
')
{ IFS= read -r BASE_BRANCH; IFS= read -r BASE_OID; } <<< "$_parsed"

if [[ -z "$PR_NODE_ID" || -z "$HEAD_BRANCH" || -z "$HEAD_OID" || -z "$HEAD_REPOSITORY" || -z "$BASE_BRANCH" || -z "$BASE_OID" || -z "$REPOSITORY" || -z "$DEFAULT_BRANCH" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"stop\", \"reason\": \"incomplete_identity\"}"
  echo "Error: PR/repository identity is incomplete; refusing base update" >&2
  exit 1
fi

# Branch names come from the GitHub API and are interpolated into git refs
# below. The refs API can create a ref whose name begins with '-', which git
# would then parse as an option.
for _ref_field in HEAD_BRANCH BASE_BRANCH DEFAULT_BRANCH; do
  _ref_value="${!_ref_field}"
  if [[ "$_ref_value" == -* ]] || ! git check-ref-format --branch "$_ref_value" >/dev/null 2>&1; then
    echo "{\"ok\": false, \"pr\": $PR, \"action\": \"stop\", \"reason\": \"invalid_ref_name\", \"field\": $(json_escape "$_ref_field")}"
    echo "Error: $_ref_field from the GitHub API is not a valid branch name: $_ref_value" >&2
    exit 1
  fi
done
unset _ref_field _ref_value

if [[ "$STATE" != "OPEN" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"skip\", \"reason\": \"not_open\", \"state\": $(json_escape "$STATE")}"
  echo "Error: PR #$PR is not OPEN ($STATE)" >&2
  exit 1
fi

if [[ "$IS_DRAFT" == "true" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"skip\", \"reason\": \"draft\"}"
  echo "Error: PR #$PR is draft - mark ready before base update/merge" >&2
  exit 1
fi

if [[ "$MERGEABLE" != "MERGEABLE" && "$MERGEABLE" != "CONFLICTING" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"stop\", \"reason\": \"unverified_initial_mergeable\", \"mergeable\": $(json_escape "$MERGEABLE"), \"mergeStateStatus\": $(json_escape "$MERGE_STATE_INITIAL")}"
  echo "Error: PR #$PR mergeability is not verified ($MERGEABLE); refresh GitHub state and retry" >&2
  exit 1
fi

if [[ "$HEAD_BRANCH" == "$DEFAULT_BRANCH" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"skip\", \"reason\": \"head_is_default\", \"head\": $(json_escape "$HEAD_BRANCH")}"
  echo "Error: refusing to update default branch head ($HEAD_BRANCH)" >&2
  exit 1
fi

# local --rebase rewrites history and force-with-lease pushes.
# Reject recognized long-lived heads before checkout/rebase. Server protection is
# not rollback for a rewritten local branch. Non-rebase GitHub branch updates still
# refuse only the live default above.
LONG_LIVED_BRANCHES=(main master dev develop trunk production prod release stable)
add_long_lived_branch() {
  local name="${1:-}"
  name="${name#refs/remotes/origin/}"
  name="${name#refs/heads/}"
  name="${name#origin/}"
  if [[ -n "$name" ]]; then
    LONG_LIVED_BRANCHES+=("$name")
  fi
}
add_long_lived_branch "$DEFAULT_BRANCH"
add_long_lived_branch "$BASE_BRANCH"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/.lattice/config.yaml" ]]; then
  configured_base=$(grep -E '^[[:space:]]*base_branch:[[:space:]]*' "$REPO_ROOT/.lattice/config.yaml" 2>/dev/null | head -1 | sed -E "s/^[[:space:]]*base_branch:[[:space:]]*//; s/[[:space:]]*[#].*$//; s/[\"']//g" | tr -d '[:space:]' || true)
  add_long_lived_branch "$configured_base"
fi
origin_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
add_long_lived_branch "$origin_head"

is_long_lived_branch() {
  local candidate
  for candidate in "${LONG_LIVED_BRANCHES[@]}"; do
    [[ "$1" == "$candidate" ]] && return 0
  done
  return 1
}

if [[ "$REBASE" == "true" ]] && is_long_lived_branch "$HEAD_BRANCH"; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"head_is_long_lived\", \"head\": $(json_escape "$HEAD_BRANCH"), \"defaultBranch\": $(json_escape "$DEFAULT_BRANCH")}"
  echo "Error: refusing local rebase/force-update of long-lived branch head ($HEAD_BRANCH); default is $DEFAULT_BRANCH" >&2
  exit 1
fi

if [[ "$REBASE" == "true" && ( "$IS_CROSS_REPOSITORY" == "true" || "$HEAD_REPOSITORY" != "$REPOSITORY" ) ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"fork_head\", \"repository\": $(json_escape "$REPOSITORY"), \"headRepository\": $(json_escape "$HEAD_REPOSITORY"), \"head\": $(json_escape "$HEAD_BRANCH")}"
  echo "Error: local --rebase only supports heads owned by $REPOSITORY; PR head belongs to $HEAD_REPOSITORY" >&2
  exit 1
fi

if [[ "$REBASE" == "true" ]]; then
  ORIGIN_FETCH_URL=$(git remote get-url origin 2>/dev/null || true)
  ORIGIN_PUSH_URL=$(git remote get-url --push origin 2>/dev/null || true)
  origin_fetch_repo_json=$(gh repo view "$ORIGIN_FETCH_URL" --json nameWithOwner 2>/dev/null || echo '{}')
  origin_push_repo_json=$(gh repo view "$ORIGIN_PUSH_URL" --json nameWithOwner 2>/dev/null || echo '{}')
  _parsed=$(python3 -c '
import json, sys
fetch = json.loads(sys.argv[1])
push = json.loads(sys.argv[2])
print(fetch.get("nameWithOwner") or "")
print(push.get("nameWithOwner") or "")
' "$origin_fetch_repo_json" "$origin_push_repo_json")
  { IFS= read -r ORIGIN_FETCH_REPOSITORY; IFS= read -r ORIGIN_PUSH_REPOSITORY; } <<< "$_parsed"
  if [[ -z "$ORIGIN_FETCH_URL" || -z "$ORIGIN_PUSH_URL" || "$ORIGIN_FETCH_REPOSITORY" != "$REPOSITORY" || "$ORIGIN_PUSH_REPOSITORY" != "$REPOSITORY" ]]; then
    echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"origin_repository_mismatch\", \"repository\": $(json_escape "$REPOSITORY"), \"originFetchRepository\": $(json_escape "$ORIGIN_FETCH_REPOSITORY"), \"originPushRepository\": $(json_escape "$ORIGIN_PUSH_REPOSITORY"), \"originFetchUrl\": $(json_escape "$ORIGIN_FETCH_URL"), \"originPushUrl\": $(json_escape "$ORIGIN_PUSH_URL")}"
    echo "Error: origin fetch/push resolve to ${ORIGIN_FETCH_REPOSITORY:-unknown}/${ORIGIN_PUSH_REPOSITORY:-unknown}, not $REPOSITORY; refusing local rebase" >&2
    exit 1
  fi
fi

if [[ "$MERGEABLE" == "CONFLICTING" && "$REBASE" != "true" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": \"stop\", \"reason\": \"conflicting\", \"conflict\": true, \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH"), \"url\": $(json_escape "$URL")}"
  echo "Error: PR #$PR is CONFLICTING with $BASE_BRANCH - resolve conflicts in the worktree, then re-run finish-work" >&2
  exit 1
fi

ACTION="none"
DETAIL=""
# diff_changed: did the update change the PR's effective diff content?
# noop leaves it false; rebase/update_branch paths set it explicitly below.
DIFF_CHANGED=false

if [[ "$REBASE" == "true" ]]; then
  ACTION="rebase"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "{\"ok\": true, \"pr\": $PR, \"action\": \"rebase\", \"dry_run\": true, \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH"), \"url\": $(json_escape "$URL")}"
    exit 0
  fi
  if ! git fetch origin \
    "+refs/heads/$BASE_BRANCH:refs/remotes/origin/$BASE_BRANCH" \
    "+refs/heads/$HEAD_BRANCH:refs/remotes/origin/$HEAD_BRANCH"; then
    echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"fetch_failed\", \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH")}"
    echo "Error: failed to fetch explicit base/head refs from origin" >&2
    exit 1
  fi
  FETCHED_HEAD_OID=$(git rev-parse "refs/remotes/origin/$HEAD_BRANCH" 2>/dev/null || true)
  if [[ "$FETCHED_HEAD_OID" != "$HEAD_OID" ]]; then
    echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"head_oid_changed\", \"expectedHeadOid\": $(json_escape "$HEAD_OID"), \"fetchedHeadOid\": $(json_escape "$FETCHED_HEAD_OID"), \"head\": $(json_escape "$HEAD_BRANCH")}"
    echo "Error: PR head changed before rebase (expected $HEAD_OID, fetched $FETCHED_HEAD_OID); refresh and retry" >&2
    exit 1
  fi
  # diff_changed probe (pre): the PR's effective diff before the update —
  # merge-base three-dot against the freshly fetched base tip.
  PRE_DIFF=""
  PRE_DIFF_OK=true
  PRE_DIFF=$(git diff "refs/remotes/origin/$BASE_BRANCH...refs/remotes/origin/$HEAD_BRANCH" 2>/dev/null) || PRE_DIFF_OK=false
  # In the standard worktree layout the head branch is checked out in its own
  # worktree, where a `git checkout` here would abort with "already checked
  # out" (and, under set -e, without the JSON summary). Rebase inside that
  # worktree instead; only fall back to a local checkout — restored afterwards
  # — when the branch is not checked out anywhere.
  HEAD_WT=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$HEAD_BRANCH" '
    $1=="worktree" { p=substr($0, 10) }
    $1=="branch" && $2==b { print p; exit }
  ')
  RESTORE_REF=""

  # An interrupted rebase leaves state that makes `git checkout` fail, so abort
  # it first. Only disarm RESTORE_REF when the checkout actually SUCCEEDED —
  # clearing it after a failed attempt would make the later EXIT-trap attempt a
  # no-op and strand the operator on the PR head.
  abort_inflight_rebase() {
    local dir="${1:-}" p
    [[ -n "$dir" ]] || return 0
    for p in rebase-merge rebase-apply; do
      p=$(git -C "$dir" rev-parse --git-path "$p" 2>/dev/null || true)
      [[ -n "$p" ]] || continue
      [[ "$p" != /* ]] && p="$dir/$p"
      if [[ -d "$p" ]]; then
        git -C "$dir" rebase --abort >/dev/null 2>&1 || true
        return 0
      fi
    done
  }

  restore_checkout() {
    abort_inflight_rebase "${WORK_DIR:-}"
    [[ -n "$RESTORE_REF" ]] || return 0
    if git checkout -q "$RESTORE_REF" 2>/dev/null; then
      RESTORE_REF=""
      return 0
    fi
    echo "Error: could not restore the original checkout ($RESTORE_REF); resolve manually" >&2
    return 1
  }

  # A signal must NOT merely run a handler and resume. Returning from an
  # INT/TERM/HUP handler continues the script, so a signal landing between the
  # rebase and the push would let the push force-with-lease the RESTORED ref's
  # HEAD into the PR branch — and the lease still matches, so it would SUCCEED,
  # publishing the wrong commits. Exit instead; EXIT then does the restore.
  on_signal() {
    echo "Error: received SIG$1 — aborting base update before any push" >&2
    exit 1
  }
  trap 'restore_checkout || true' EXIT
  for _sig in INT TERM HUP; do
    # shellcheck disable=SC2064 # expand $_sig now, at trap-definition time
    trap "on_signal $_sig" "$_sig"
  done
  unset _sig
  if [[ -n "$HEAD_WT" ]]; then
    WORK_DIR="$HEAD_WT"
  else
    WORK_DIR=$(pwd)
    ORIGINAL_REF=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse HEAD)
    checkout_ok=true
    # No `--` here: `git checkout -- <name>` means PATHSPEC, not branch. The
    # option-injection guard for these names is the check-ref-format validation
    # applied to HEAD_BRANCH/BASE_BRANCH right after the API parse.
    if git show-ref --verify --quiet "refs/heads/$HEAD_BRANCH"; then
      git checkout -q "$HEAD_BRANCH" 2>/dev/null || checkout_ok=false
    else
      git checkout -q -B "$HEAD_BRANCH" "origin/$HEAD_BRANCH" 2>/dev/null || checkout_ok=false
    fi
    if [[ "$checkout_ok" != "true" ]]; then
      echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"checkout_failed\", \"head\": $(json_escape "$HEAD_BRANCH")}"
      echo "Error: cannot check out $HEAD_BRANCH for rebase" >&2
      exit 1
    fi
    RESTORE_REF="$ORIGINAL_REF"
  fi
  # The fetch above refreshed origin/$HEAD_BRANCH, so a bare --force-with-lease
  # would pass even when the local branch is missing remote-only commits and the
  # push would erase them. Reconcile with the remote tip before rewriting history.
  if git -C "$WORK_DIR" rev-parse --verify --quiet "origin/$HEAD_BRANCH" >/dev/null; then
    if git -C "$WORK_DIR" merge-base --is-ancestor HEAD "origin/$HEAD_BRANCH"; then
      if ! git -C "$WORK_DIR" merge --ff-only "origin/$HEAD_BRANCH" >/dev/null; then
        echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"ff_update_failed\", \"head\": $(json_escape "$HEAD_BRANCH")}"
        echo "Error: fast-forward of $HEAD_BRANCH to origin/$HEAD_BRANCH failed" >&2
        restore_checkout
        exit 1
      fi
    elif git -C "$WORK_DIR" merge-base --is-ancestor "origin/$HEAD_BRANCH" HEAD; then
      # Local branch is AHEAD of origin: the push below would publish the
      # unpushed commits into the PR. Refuse unless explicitly allowed.
      if [[ "$ALLOW_LOCAL_AHEAD" != "true" ]]; then
        AHEAD_COUNT=$(git -C "$WORK_DIR" rev-list --count "origin/$HEAD_BRANCH..HEAD" 2>/dev/null || echo "?")
        echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"local_ahead\", \"aheadBy\": $(json_escape "$AHEAD_COUNT"), \"head\": $(json_escape "$HEAD_BRANCH")}"
        echo "Error: local $HEAD_BRANCH is $AHEAD_COUNT commit(s) ahead of origin/$HEAD_BRANCH - pushing would publish unpushed work into the PR; push first or pass --allow-local-ahead" >&2
        restore_checkout
        exit 1
      fi
    else
      echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"stale_local_diverged\", \"head\": $(json_escape "$HEAD_BRANCH")}"
      echo "Error: local $HEAD_BRANCH and origin/$HEAD_BRANCH have diverged - reconcile (pull/rebase onto origin/$HEAD_BRANCH) before --rebase" >&2
      restore_checkout
      exit 1
    fi
  fi
  if ! git -C "$WORK_DIR" rebase "origin/$BASE_BRANCH"; then
    # Distinguish a conflicted rebase (in-flight rebase state exists) from a
    # rebase that failed to start (e.g. dirty worktree).
    REBASE_CONFLICT=false
    for _p in rebase-merge rebase-apply; do
      _pp=$(git -C "$WORK_DIR" rev-parse --git-path "$_p" 2>/dev/null || true)
      [[ -n "$_pp" ]] || continue
      [[ "$_pp" != /* ]] && _pp="$WORK_DIR/$_pp"
      [[ -d "$_pp" ]] && REBASE_CONFLICT=true
    done
    unset _p _pp
    git -C "$WORK_DIR" rebase --abort 2>/dev/null || true
    echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"rebase_failed\", \"conflict\": $REBASE_CONFLICT, \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH")}"
    echo "Error: rebase onto origin/$BASE_BRANCH failed (conflicts or dirty worktree) - resolve in worktree" >&2
    restore_checkout
    exit 1
  fi
  if ! git -C "$WORK_DIR" push --force-with-lease="refs/heads/$HEAD_BRANCH:$HEAD_OID" origin "HEAD:refs/heads/$HEAD_BRANCH"; then
    echo "{\"ok\": false, \"pr\": $PR, \"action\": \"rebase\", \"reason\": \"push_failed\", \"head\": $(json_escape "$HEAD_BRANCH")}"
    echo "Error: force-with-lease push failed for $HEAD_BRANCH" >&2
    restore_checkout
    exit 1
  fi
  # diff_changed probe (post): the rebased head against the same base tip.
  POST_DIFF=""
  POST_DIFF_OK=true
  POST_DIFF=$(git -C "$WORK_DIR" diff "refs/remotes/origin/$BASE_BRANCH...HEAD" 2>/dev/null) || POST_DIFF_OK=false
  if [[ "$PRE_DIFF_OK" == "true" && "$POST_DIFF_OK" == "true" && "$PRE_DIFF" == "$POST_DIFF" ]]; then
    DIFF_CHANGED=false
  else
    DIFF_CHANGED=true
  fi
  restore_checkout
  DETAIL="rebased onto origin/${BASE_BRANCH} and force-with-lease pushed"
else
  case "$MERGE_STATE_INITIAL" in
    CLEAN|BLOCKED|HAS_HOOKS|UNSTABLE)
      ACTION="noop"
      DETAIL="already up to date (mergeStateStatus=$MERGE_STATE_INITIAL)"
      ;;
    BEHIND)
      ACTION="update_branch"
      ;;
    *)
      echo "{\"ok\": false, \"pr\": $PR, \"action\": \"stop\", \"reason\": \"unverified_initial_state\", \"mergeable\": $(json_escape "$MERGEABLE"), \"mergeStateStatus\": $(json_escape "$MERGE_STATE_INITIAL"), \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH")}"
      echo "Error: PR #$PR base state is not verifiable ($MERGE_STATE_INITIAL); refresh GitHub state and retry" >&2
      exit 1
      ;;
  esac
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "{\"ok\": true, \"pr\": $PR, \"action\": $(json_escape "$ACTION"), \"dry_run\": true, \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH"), \"mergeable\": $(json_escape "$MERGEABLE"), \"mergeStateStatus\": $(json_escape "$MERGE_STATE_INITIAL"), \"url\": $(json_escape "$URL")}"
    exit 0
  fi
  if [[ "$ACTION" == "update_branch" ]]; then
    # diff_changed probe (pre): capture the PR's effective diff from GitHub
    # before the update. Server-side, so it needs no local clone of the PR
    # objects and never fetches into the operator's cwd repository.
    PRE_PR_DIFF=""
    PRE_PR_DIFF_OK=true
    PRE_PR_DIFF=$(gh pr diff "$PR" 2>/dev/null) || PRE_PR_DIFF_OK=false
    # The mutation merges base into head only when the server still sees the
    # exact head OID inspected above. A concurrent head update fails closed.
    update_query='mutation UpdatePullRequestBranch($pullRequestId: ID!, $expectedHeadOid: GitObjectID!) { updatePullRequestBranch(input: {pullRequestId: $pullRequestId, expectedHeadOid: $expectedHeadOid, updateMethod: MERGE}) { pullRequest { headRefOid } } }'
    if ! upd_out=$(gh api graphql \
      -f query="$update_query" \
      -f pullRequestId="$PR_NODE_ID" \
      -f expectedHeadOid="$HEAD_OID" 2>&1); then
      echo "{\"ok\": false, \"pr\": $PR, \"action\": \"update_branch\", \"reason\": \"update_failed\", \"detail\": $(json_escape "$upd_out"), \"base\": $(json_escape "$BASE_BRANCH")}"
      echo "Error: GitHub updatePullRequestBranch failed: $upd_out" >&2
      echo "Hint: enable Allow edits from maintainers / update branch permission, or resolve locally and push." >&2
      exit 1
    fi
    DETAIL="$upd_out"
  fi
fi

MERGEABLE2=""
MERGE_STATE=""
HEAD_OID2=""
for attempt in 1 2 3 4 5; do
  view2=$(gh pr view "$PR" --json mergeable,mergeStateStatus,headRefOid 2>/dev/null || echo '{}')
  _parsed=$(python3 -c '
import json, sys
view = json.loads(sys.argv[1])
print(view.get("mergeable") or "")
print(view.get("mergeStateStatus") or "")
print(view.get("headRefOid") or "")
' "$view2")
  { IFS= read -r MERGEABLE2; IFS= read -r MERGE_STATE; IFS= read -r HEAD_OID2; } <<< "$_parsed"
  if [[ -n "$HEAD_OID2" && "$MERGE_STATE" != "UNKNOWN" && -n "$MERGE_STATE" ]]; then
    break
  fi
  if [[ "$attempt" -lt 5 ]]; then sleep 1; fi
done

if [[ "$MERGEABLE2" == "CONFLICTING" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": $(json_escape "$ACTION"), \"reason\": \"conflicting_after_update\", \"conflict\": true, \"mergeable\": \"CONFLICTING\", \"mergeStateStatus\": $(json_escape "$MERGE_STATE"), \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH"), \"detail\": $(json_escape "$DETAIL")}"
  echo "Error: PR #$PR still CONFLICTING after $ACTION - resolve conflicts, then re-run" >&2
  exit 1
fi

if [[ "$MERGEABLE2" != "MERGEABLE" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": $(json_escape "$ACTION"), \"reason\": \"unverified_mergeable_after_update\", \"mergeable\": $(json_escape "$MERGEABLE2"), \"mergeStateStatus\": $(json_escape "$MERGE_STATE"), \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH"), \"detail\": $(json_escape "$DETAIL")}"
  echo "Error: PR #$PR mergeability is not verified after $ACTION ($MERGEABLE2)" >&2
  exit 1
fi

if [[ "$MERGE_STATE" == "BEHIND" ]]; then
  echo "{\"ok\": false, \"pr\": $PR, \"action\": $(json_escape "$ACTION"), \"reason\": \"behind_after_update\", \"mergeable\": $(json_escape "$MERGEABLE2"), \"mergeStateStatus\": \"BEHIND\", \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH"), \"detail\": $(json_escape "$DETAIL")}"
  echo "Error: PR #$PR is still BEHIND after $ACTION" >&2
  exit 1
fi

case "$MERGE_STATE" in
  CLEAN|BLOCKED|HAS_HOOKS|UNSTABLE) ;;
  *)
    echo "{\"ok\": false, \"pr\": $PR, \"action\": $(json_escape "$ACTION"), \"reason\": \"unverified_after_update\", \"mergeable\": $(json_escape "$MERGEABLE2"), \"mergeStateStatus\": $(json_escape "$MERGE_STATE"), \"base\": $(json_escape "$BASE_BRANCH"), \"head\": $(json_escape "$HEAD_BRANCH"), \"detail\": $(json_escape "$DETAIL")}"
    echo "Error: PR #$PR state is not verified after $ACTION ($MERGE_STATE)" >&2
    exit 1
    ;;
esac

if [[ "$ACTION" == "update_branch" ]]; then
  # diff_changed probe (post): compare against the pre-update capture.
  # Any probe failure degrades to true (unknown diff voids prior verdicts).
  DIFF_CHANGED=true
  POST_PR_DIFF=""
  POST_PR_DIFF_OK=true
  POST_PR_DIFF=$(gh pr diff "$PR" 2>/dev/null) || POST_PR_DIFF_OK=false
  if [[ "$PRE_PR_DIFF_OK" == "true" && "$POST_PR_DIFF_OK" == "true" && "$PRE_PR_DIFF" == "$POST_PR_DIFF" ]]; then
    DIFF_CHANGED=false
  fi
fi

echo "{\"ok\": true, \"pr\": $PR, \"action\": $(json_escape "$ACTION"), \"diff_changed\": $DIFF_CHANGED, \"conflict\": false, \"mergeable\": $(json_escape "$MERGEABLE2"), \"mergeStateStatus\": $(json_escape "$MERGE_STATE"), \"base\": $(json_escape "$BASE_BRANCH"), \"baseOid\": $(json_escape "$BASE_OID"), \"head\": $(json_escape "$HEAD_BRANCH"), \"headOid\": $(json_escape "$HEAD_OID2"), \"headRepository\": $(json_escape "$HEAD_REPOSITORY"), \"url\": $(json_escape "$URL"), \"detail\": $(json_escape "$DETAIL")}"
exit 0
