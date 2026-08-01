#!/usr/bin/env bash
# List GitHub Project board items as Lattice tkt-N candidates (automation trigger plane).
#
# Canonical home: skills/_lattice-lib/scripts/.
# Consumers poll Ready (or LATTICE_TRIGGER_STATUS) through this helper instead of
# inventing per-consumer `gh project item-list` wrappers.
#
# Usage:
#   list-board-items.sh [--owner OWNER] [--project NUMBER] [--status STATUS]
#                       [--repository OWNER/REPO | --all-repositories]
#                       [--limit N] [--include-epic] [--json] [--help]
#
# Defaults:
#   owner/number: LATTICE_GITHUB_PROJECT_OWNER / LATTICE_GITHUB_PROJECT_NUMBER
#                 (process env, else MAIN_ROOT .env / .env.local — same keys as github-project-add)
#   status:       LATTICE_TRIGGER_STATUS or Ready
#   limit:        100
#
# Output (default): one current-repository `tkt-<issue-number>` per line.
#   --json: JSON array of {tkt, number, title, status, labels, url, repository}
#   --all-repositories requires --json; cross-repo inventory never emits bare tkt-N.
#
# Filters (contract):
#   - content.type == "Issue" and content.number present
#   - status field equals --status (client-side pin; also pass --query status:"…" to gh)
#   - exclude label `epic` unless --include-epic
#
# Exit: 0 on success (including empty list); 1 on usage/config/gh/jq failure.
# Logs → stderr.
#
# Pinned gh JSON shape (bats mock this; drift → fail tests):
#   { "items": [ {
#       "content": { "number": 1, "type": "Issue", "title": "…", "url": "…",
#                    "repository": "owner/repo" },
#       "status": "Ready",
#       "labels": ["bug"],
#       "title": "…",
#       "id": "PVTI_…"
#   } ] }
#
# Requires: `gh` with project scope, `jq`.

set -euo pipefail

log() { printf 'list-board-items: %s\n' "$*" >&2; }

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

# --- MAIN_ROOT (inline; keep aligned with github-project-add / _lattice-home) ---
main_root() {
  local repo_root git_common root
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  repo_root=$(git rev-parse --show-toplevel)
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    git_common=$(git rev-parse --git-common-dir)
    [[ "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  if [[ "$git_common" == */.git ]]; then
    root="${git_common%/.git}"
  elif [[ "$git_common" == */.git/* ]]; then
    root="${git_common%%/.git/*}"
  else
    root="$repo_root"
  fi
  printf '%s' "$root"
}

load_dotenv_file_into() {
  local file="$1"
  [[ -f "$file" && -r "$file" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    case "$key" in
      LATTICE_GITHUB_PROJECT_OWNER | LATTICE_GITHUB_PROJECT_NUMBER | LATTICE_TRIGGER_STATUS) ;;
      *) continue ;;
    esac
    # Quoted value: the quoted span IS the value — a ` # ` inside quotes is
    # data, anything after the closing quote (e.g. a comment) is dropped.
    # Unquoted: strip from the first ` #` (space-hash); `value#fragment`
    # without the space keeps the hash (documented dotenv behavior).
    if [[ "$val" == \"* ]]; then
      val="${val#\"}"
      val="${val%%\"*}"
    elif [[ "$val" == \'* ]]; then
      val="${val#\'}"
      val="${val%%\'*}"
    else
      if [[ "$val" == *" #"* ]]; then
        val="${val%% #*}"
      fi
      val="${val%"${val##*[![:space:]]}"}"
    fi
    case "$key" in
      LATTICE_GITHUB_PROJECT_OWNER) FILE_OWNER="$val" ;;
      LATTICE_GITHUB_PROJECT_NUMBER) FILE_NUMBER="$val" ;;
      LATTICE_TRIGGER_STATUS) FILE_TRIGGER_STATUS="$val" ;;
    esac
  done <"$file"
}

OWNER=""
NUMBER=""
STATUS=""
LIMIT=100
INCLUDE_EPIC=false
JSON_OUT=false
REPOSITORY=""
ALL_REPOSITORIES=false
FILE_OWNER=""
FILE_NUMBER=""
FILE_TRIGGER_STATUS=""

require_value() {
  # $1 = flag name, $2 = next argv (may be empty)
  local flag="$1" val="${2-}"
  if [[ $# -lt 2 || -z "$val" || "$val" == -* ]]; then
    log "$flag requires a value"
    usage >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      require_value "$1" "${2-}"
      OWNER="$2"
      shift 2
      ;;
    --owner=*)
      OWNER="${1#--owner=}"
      [[ -n "$OWNER" ]] || { log "--owner requires a value"; usage >&2; exit 1; }
      shift
      ;;
    --project | --number)
      require_value "$1" "${2-}"
      NUMBER="$2"
      shift 2
      ;;
    --project=* | --number=*)
      NUMBER="${1#*=}"
      [[ -n "$NUMBER" ]] || { log "--project requires a value"; usage >&2; exit 1; }
      shift
      ;;
    --status)
      require_value "$1" "${2-}"
      STATUS="$2"
      shift 2
      ;;
    --status=*)
      STATUS="${1#--status=}"
      [[ -n "$STATUS" ]] || { log "--status requires a value"; usage >&2; exit 1; }
      shift
      ;;
    --limit)
      require_value "$1" "${2-}"
      LIMIT="$2"
      shift 2
      ;;
    --limit=*)
      LIMIT="${1#--limit=}"
      [[ -n "$LIMIT" ]] || { log "--limit requires a value"; usage >&2; exit 1; }
      shift
      ;;
    --include-epic)
      INCLUDE_EPIC=true
      shift
      ;;
    --repository)
      require_value "$1" "${2-}"
      REPOSITORY="$2"
      shift 2
      ;;
    --repository=*)
      REPOSITORY="${1#--repository=}"
      [[ -n "$REPOSITORY" ]] || { log "--repository requires a value"; usage >&2; exit 1; }
      shift
      ;;
    --all-repositories)
      ALL_REPOSITORIES=true
      shift
      ;;
    --json)
      JSON_OUT=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      log "unknown flag: $1"
      usage >&2
      exit 1
      ;;
    *)
      log "unexpected argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if $ALL_REPOSITORIES && [[ -n "$REPOSITORY" ]]; then
  log "--repository and --all-repositories are mutually exclusive"
  exit 1
fi
if $ALL_REPOSITORIES && ! $JSON_OUT; then
  log "--all-repositories requires --json so repository identity is preserved"
  exit 1
fi

ROOT=""
if ROOT=$(main_root 2>/dev/null); then
  load_dotenv_file_into "$ROOT/.env"
  load_dotenv_file_into "$ROOT/.env.local"
fi

# Prefer non-empty process env, else MAIN_ROOT dotenv, else (status only) Ready.
# Empty-string env does not block .env fill (treat as unset).
if [[ -z "$OWNER" ]]; then
  if [[ -n "${LATTICE_GITHUB_PROJECT_OWNER:-}" ]]; then
    OWNER="$LATTICE_GITHUB_PROJECT_OWNER"
  else
    OWNER="$FILE_OWNER"
  fi
fi
if [[ -z "$NUMBER" ]]; then
  if [[ -n "${LATTICE_GITHUB_PROJECT_NUMBER:-}" ]]; then
    NUMBER="$LATTICE_GITHUB_PROJECT_NUMBER"
  else
    NUMBER="$FILE_NUMBER"
  fi
fi
if [[ -z "$STATUS" ]]; then
  if [[ -n "${LATTICE_TRIGGER_STATUS:-}" ]]; then
    STATUS="$LATTICE_TRIGGER_STATUS"
  elif [[ -n "$FILE_TRIGGER_STATUS" ]]; then
    STATUS="$FILE_TRIGGER_STATUS"
  else
    STATUS="Ready"
  fi
fi

OWNER="${OWNER#"${OWNER%%[![:space:]]*}"}"
OWNER="${OWNER%"${OWNER##*[![:space:]]}"}"
NUMBER="${NUMBER#"${NUMBER%%[![:space:]]*}"}"
NUMBER="${NUMBER%"${NUMBER##*[![:space:]]}"}"
STATUS="${STATUS#"${STATUS%%[![:space:]]*}"}"
STATUS="${STATUS%"${STATUS##*[![:space:]]}"}"

if [[ -z "$OWNER" || -z "$NUMBER" ]]; then
  log "need --owner/--project or LATTICE_GITHUB_PROJECT_OWNER + LATTICE_GITHUB_PROJECT_NUMBER"
  exit 1
fi
# A `.env` shipped by a cloned repo can point these at a third-party board that
# then gets read with the user's token. Never silent: say which board is being
# queried and that a repo file chose it.
if [[ -n "$FILE_OWNER$FILE_NUMBER" ]] \
  && { [[ "$OWNER" == "$FILE_OWNER" && -z "${LATTICE_GITHUB_PROJECT_OWNER:-}" ]] \
    || [[ "$NUMBER" == "$FILE_NUMBER" && -z "${LATTICE_GITHUB_PROJECT_NUMBER:-}" ]]; }; then
  log "board target from repository .env: owner=$OWNER project=$NUMBER (override with --owner/--project or the environment)"
fi
if ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
  log "project number must be digits (got '$NUMBER')"
  exit 1
fi
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -lt 1 ]]; then
  log "limit must be positive integer (got '$LIMIT')"
  exit 1
fi
if [[ -z "$STATUS" ]]; then
  log "status must be non-empty"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  log "gh not on PATH"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  log "jq not on PATH"
  exit 1
fi

if ! $ALL_REPOSITORIES; then
  if [[ -z "$REPOSITORY" ]]; then
    REPOSITORY=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  fi
  REPOSITORY="${REPOSITORY%.git}"
  if [[ ! "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    log "cannot resolve current repository identity; use --repository OWNER/REPO or --all-repositories --json"
    exit 1
  fi
fi

# Server-side filter (Projects filter syntax). Client re-pins .status below.
# Always quote the status value so multi-word columns (e.g. "In progress")
# parse as one token — unquoted `status:In progress` is misread by the filter.
STATUS_Q="${STATUS//\"/\\\"}"
QUERY="status:\"${STATUS_Q}\""

# Keep stderr separate from stdout (like gh_issue_view_json in the sibling
# github-issue-parent-add.sh): success-path gh warnings on stderr must not
# corrupt the JSON handed to jq below.
RAW=""
GH_ERR=""
GH_ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/list-board-gh-err.XXXXXX")
trap 'rm -f "$GH_ERR_FILE"' EXIT
status=0
RAW=$(gh project item-list "$NUMBER" \
  --owner "$OWNER" \
  --format json \
  --limit "$LIMIT" \
  --query "$QUERY" 2>"$GH_ERR_FILE") || status=$?
GH_ERR=$(cat "$GH_ERR_FILE" 2>/dev/null || true)

if [[ $status -ne 0 ]]; then
  if printf '%s\n%s' "$RAW" "$GH_ERR" | grep -qiE 'INSUFFICIENT_SCOPES|required scopes|read:project|project.*scope'; then
    log "gh missing project scope — run: gh auth refresh -s project"
  fi
  log "gh project item-list failed"
  log "detail: ${GH_ERR:-$RAW}"
  exit 1
fi

# --query is a SERVER-side filter only on github.com and GHES >= 3.20; older
# GHES ignores it and returns the first $LIMIT items unfiltered, so Ready items
# past that cut vanish silently. A full page is the only detectable symptom.
RAW_COUNT=$(printf '%s' "$RAW" | jq -r '(.items // []) | length' 2>/dev/null || echo 0)
if [[ "$RAW_COUNT" =~ ^[0-9]+$ && "$RAW_COUNT" -ge "$LIMIT" ]]; then
  log "WARNING: gh returned a full page ($RAW_COUNT of --limit $LIMIT); items beyond it are not visible. Raise --limit to confirm nothing is missing."
fi

# jq: pin content.type + status + optional epic filter
# labels may be null or absent on some hosts — coerce to [].
INCLUDE_EPIC_JSON=false
$INCLUDE_EPIC && INCLUDE_EPIC_JSON=true

FILTERED=$(printf '%s' "$RAW" | jq -c \
  --arg status "$STATUS" \
  --arg repository "$REPOSITORY" \
  --argjson all_repositories "$ALL_REPOSITORIES" \
  --argjson include_epic "$INCLUDE_EPIC_JSON" '
  (.items // [])
  | map(select(
      (.content.type // "") == "Issue"
      and (.content.number | type == "number")
      and ((.status // "") == $status)
      and ((.content.repository // .repository // "") != "")
      and (
        $all_repositories
        or ((.content.repository // .repository // "") | ascii_downcase) == ($repository | ascii_downcase)
      )
      and (
        $include_epic
        or ((.labels // []) | map(ascii_downcase) | index("epic") | not)
      )
    ))
  | map({
      tkt: ("tkt-" + (.content.number | tostring)),
      number: .content.number,
      title: (.content.title // .title // ""),
      status: (.status // ""),
      labels: (.labels // []),
      url: (.content.url // ""),
      repository: (.content.repository // .repository // "")
    })
') || {
  log "jq parse failed — unexpected gh JSON shape (pin bats fixture)"
  exit 1
}

MISSING_REPOSITORY_COUNT=$(printf '%s' "$RAW" | jq -r '
  [(.items // [])[] | select((.content.type // "") == "Issue" and ((.content.repository // .repository // "") == ""))] | length
' 2>/dev/null || echo 0)
if [[ "$MISSING_REPOSITORY_COUNT" != "0" ]]; then
  log "skipped $MISSING_REPOSITORY_COUNT issue item(s) without repository identity"
fi

if $JSON_OUT; then
  printf '%s\n' "$FILTERED"
else
  printf '%s' "$FILTERED" | jq -r '.[].tkt'
fi

exit 0
