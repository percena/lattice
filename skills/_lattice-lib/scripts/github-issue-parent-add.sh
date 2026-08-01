#!/usr/bin/env bash
# Best-effort: link a child GitHub issue as a sub-issue of a parent.
#
# Canonical home: skills/_lattice-lib/scripts/. Callers:
#   create-tickets (multi-ticket under Spec primary #N)
#
# Usage:
#   bash github-issue-parent-add.sh --parent <N|url> --child <N|url>
#   bash github-issue-parent-add.sh <parent> <child>
#
# Exit: always 0 (soft-fail). Missing args / gh / API failure → log on stderr, exit 0.
# Never blocks issue create or binder write.
#
# Resolution order (first success wins):
#   1) gh issue edit CHILD --set-parent PARENT   (CLI >=2.94 when available)
#   2) gh issue edit PARENT --add-sub-issue CHILD (CLI >=2.94 when available)
#   3) GraphQL addSubIssue (node ids; GraphQL-Features: sub_issues)
#   4) REST POST .../issues/{parent}/sub_issues  (database id of child)
#
# Parent and child may be bare issue numbers or https://github.com/o/r/issues/N URLs.
# Repo context: current git remote (gh default) unless URLs embed owner/repo.

set -uo pipefail

log() { printf 'github-issue-parent-add: %s\n' "$*" >&2; }

PARENT=""
CHILD=""

# Soft-fail scripts: missing value flags must log + exit 0, never hang.
# (`shift 2 || true` leaves $1 forever when only the flag is present.)
require_flag_value_or_skip() {
  local flag="$1" val="${2-}"
  if [[ $# -lt 2 || -z "$val" || "$val" == -* ]]; then
    log "$flag requires a value — skip"
    exit 0
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent)
      require_flag_value_or_skip "$1" "${2-}"
      PARENT="$2"
      shift 2
      ;;
    --parent=*)
      PARENT="${1#--parent=}"
      if [[ -z "$PARENT" ]]; then
        log "--parent requires a value — skip"
        exit 0
      fi
      shift
      ;;
    --child)
      require_flag_value_or_skip "$1" "${2-}"
      CHILD="$2"
      shift 2
      ;;
    --child=*)
      CHILD="${1#--child=}"
      if [[ -z "$CHILD" ]]; then
        log "--child requires a value — skip"
        exit 0
      fi
      shift
      ;;
    -h | --help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      log "unknown flag: $1 (ignored)"
      shift
      ;;
    *)
      if [[ -z "$PARENT" ]]; then
        PARENT="$1"
      elif [[ -z "$CHILD" ]]; then
        CHILD="$1"
      else
        log "extra arg ignored: $1"
      fi
      shift
      ;;
  esac
done

PARENT="${PARENT//[$'\t\r\n ']/}"
CHILD="${CHILD//[$'\t\r\n ']/}"

if [[ -z "$PARENT" || -z "$CHILD" ]]; then
  log "need --parent and --child — skip"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  log "gh not on PATH — skip"
  exit 0
fi

# Extract trailing issue number from URL or bare digits.
issue_number() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf '%s' "$raw"
    return 0
  fi
  if [[ "$raw" =~ /issues/([0-9]+)([/?#]|$) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  # URL-shaped input that is not an /issues/ URL (e.g. /pull/, /discussions/)
  # must fail loudly: the trailing-digits fallback would parse the wrong number
  # and bypass the cross-repo guard (issue_repo_from_url only matches
  # /issues/ URLs). Non-URL inputs (bare N, #N, tkt-N) keep the fallback.
  # Covers scheme URLs, SSH remotes (git@host:...), and case-variant bare hosts.
  local lowered
  lowered=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  if [[ "$raw" == *://* || "$raw" == *@*:* || "$lowered" == github.com/* || "$lowered" == www.github.com/* ]]; then
    log "URL is not a GitHub /issues/ URL (PRs/discussions are not issues): $raw"
    return 1
  fi
  if [[ "$raw" =~ ([0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# owner/repo from issue URL when present; else empty (use gh default repo).
# Host matches case-insensitively and accepts both https (github.com/) and
# SSH-remote (git@github.com:) forms so the cross-repo guard cannot
# be bypassed by an equivalent spelling of the same URL.
issue_repo_from_url() {
  local raw="$1"
  # Owner/name charset is pinned: [^/] would admit '?', '#' and '..', which
  # would then land in the gh api REST path built from this value.
  if [[ "$raw" =~ [gG][iI][tT][hH][uU][bB]\.[cC][oO][mM][:/]([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/issues/[0-9]+ ]]; then
    # Reject traversal-shaped components ('.', '..'): this value becomes a
    # path segment in the gh api REST path built below.
    case "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" in
      */.|*/..|./*|../*) return 1 ;;
    esac
    printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

PARENT_N=""
CHILD_N=""
if ! PARENT_N=$(issue_number "$PARENT"); then
  log "cannot parse parent issue number from '$PARENT' — skip"
  exit 0
fi
if ! CHILD_N=$(issue_number "$CHILD"); then
  log "cannot parse child issue number from '$CHILD' — skip"
  exit 0
fi

if [[ "$PARENT_N" == "$CHILD_N" ]]; then
  log "parent and child are the same (#$PARENT_N) — skip"
  exit 0
fi

# Optional --repo owner/repo (empty = gh default). Avoid empty-array + set -u.
# when both sides embed owner/repo, they must agree — never
# apply a child number from repo A as a sub-issue under parent in repo B.
REPO_SLUG=""
PARENT_REPO=""
CHILD_REPO=""
PARENT_REPO=$(issue_repo_from_url "$PARENT" 2>/dev/null || true)
CHILD_REPO=$(issue_repo_from_url "$CHILD" 2>/dev/null || true)
if [[ -n "$PARENT_REPO" && -n "$CHILD_REPO" && "$PARENT_REPO" != "$CHILD_REPO" ]]; then
  log "cross-repository parent/child refused before mutation: parent=$PARENT_REPO child=$CHILD_REPO"
  exit 0
fi
if [[ -n "$PARENT_REPO" ]]; then
  REPO_SLUG="$PARENT_REPO"
elif [[ -n "$CHILD_REPO" ]]; then
  REPO_SLUG="$CHILD_REPO"
fi

gh_issue_edit() {
  if [[ -n "$REPO_SLUG" ]]; then
    gh issue edit --repo "$REPO_SLUG" "$@"
  else
    gh issue edit "$@"
  fi
}

gh_issue_view_json() {
  local num="$1"
  if [[ -n "$REPO_SLUG" ]]; then
    gh issue view "$num" --repo "$REPO_SLUG" --json id,number 2>/dev/null
  else
    gh issue view "$num" --json id,number 2>/dev/null
  fi
}

# --- Path 1/2: native gh flags when the installed CLI advertises them ---
gh_edit_help=$(gh issue edit --help 2>&1 || true)

try_gh_edit_flag() {
  local out status=0
  out=$(gh_issue_edit "$@" 2>&1) || status=$?
  if [[ $status -eq 0 ]]; then
    return 0
  fi
  # A conflict naming a DIFFERENT parent is a real failure, never an
  # idempotent success ("child already has a parent" != "same parent").
  if printf '%s' "$out" | grep -qiE 'already has a( different)? parent|different parent'; then
    log "gh issue edit failed: $out"
    return 1
  fi
  # Genuine idempotent duplicate: the requested link itself already exists.
  if printf '%s' "$out" | grep -qiE 'already exists|duplicate|same parent|is already a sub'; then
    log "already linked parent #$PARENT_N <- child #$CHILD_N"
    return 0
  fi
  # "already"-ish but unclassifiable: do not claim success (soft-fail overall).
  if printf '%s' "$out" | grep -qi 'already'; then
    log "parent link attempt ambiguous: $out"
    return 1
  fi
  log "gh issue edit failed: $out"
  return 1
}

if printf '%s' "$gh_edit_help" | grep -qE -- '--set-parent'; then
  if try_gh_edit_flag "$CHILD_N" --set-parent "$PARENT_N"; then
    log "linked via gh --set-parent: parent #$PARENT_N <- child #$CHILD_N"
    exit 0
  fi
fi

if printf '%s' "$gh_edit_help" | grep -qE -- '--add-sub-issue'; then
  if try_gh_edit_flag "$PARENT_N" --add-sub-issue "$CHILD_N"; then
    log "linked via gh --add-sub-issue: parent #$PARENT_N <- child #$CHILD_N"
    exit 0
  fi
fi

# --- Path 3: GraphQL addSubIssue (node id / GraphQL id) ---
parent_gql=""
child_gql=""
parent_json=$(gh_issue_view_json "$PARENT_N" || true)
child_json=$(gh_issue_view_json "$CHILD_N" || true)

if [[ -n "$parent_json" && -n "$child_json" ]]; then
  parent_gql=$(printf '%s' "$parent_json" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  child_gql=$(printf '%s' "$child_json" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [[ -n "$parent_gql" && -n "$child_gql" ]]; then
  gql_out=""
  gql_status=0
  # shellcheck disable=SC2016
  gql_out=$(gh api graphql \
    -H "GraphQL-Features: sub_issues" \
    -f query='mutation($parent:ID!,$child:ID!){
      addSubIssue(input:{issueId:$parent,subIssueId:$child}){
        issue{number}
        subIssue{number}
      }
    }' \
    -f parent="$parent_gql" \
    -f child="$child_gql" 2>&1) || gql_status=$?

  if [[ $gql_status -eq 0 ]]; then
    log "linked via GraphQL addSubIssue: parent #$PARENT_N <- child #$CHILD_N"
    exit 0
  fi
  if printf '%s' "$gql_out" | grep -qiE 'already|duplicate|exists'; then
    log "already linked (GraphQL): parent #$PARENT_N <- child #$CHILD_N"
    exit 0
  fi
  log "GraphQL addSubIssue failed (will try REST): $gql_out"
fi

# --- Path 4: REST sub_issues (database id, not node_id) ---
repo_for_rest=""
if [[ -n "$REPO_SLUG" ]]; then
  repo_for_rest="$REPO_SLUG"
else
  repo_for_rest=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi

if [[ -z "$repo_for_rest" ]]; then
  log "cannot resolve owner/repo for REST fallback — skip"
  exit 0
fi

child_db_id=""
child_db_id=$(gh api "repos/${repo_for_rest}/issues/${CHILD_N}" --jq .id 2>/dev/null || true)
if [[ -z "$child_db_id" || ! "$child_db_id" =~ ^[0-9]+$ ]]; then
  log "cannot resolve database id for child #$CHILD_N — skip"
  exit 0
fi

rest_out=""
rest_status=0
# -F (typed field), not -f (string): the endpoint requires sub_issue_id as an
# integer; a string value is a 422 → silent soft-fail on the gh<2.94 path.
rest_out=$(gh api \
  -X POST \
  "repos/${repo_for_rest}/issues/${PARENT_N}/sub_issues" \
  -F "sub_issue_id=${child_db_id}" 2>&1) || rest_status=$?

if [[ $rest_status -eq 0 ]]; then
  log "linked via REST sub_issues: parent #$PARENT_N <- child #$CHILD_N"
  exit 0
fi
if printf '%s' "$rest_out" | grep -qiE 'already|duplicate|exists'; then
  log "already linked (REST): parent #$PARENT_N <- child #$CHILD_N"
  exit 0
fi

log "parent link failed (non-fatal): parent #$PARENT_N <- child #$CHILD_N"
log "detail: $rest_out"
exit 0
