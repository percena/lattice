#!/usr/bin/env bash
# Check for duplicate work before creating a new ticket or starting work.
#
# Canonical home: skills/_lattice-lib/scripts/.
#
# Lattice-native adaptation of ERP's check-duplicate-work.mjs pattern.
# GitHub-native: 3 surfaces (open issues, local worktrees, open PRs) —
# Lattice has no separate tracker queue (GitHub issue IS the tracker).
#
# Usage:
#   check-duplicate-work.sh --title "proposed ticket title" [options]
#
# Options:
#   --title TITLE        proposed ticket title (required)
#   --repository REPO    GitHub repo (default: auto-detect from git remote)
#   --skip-remote        skip open PR surface (faster; use at filing time)
#   --json               JSON output on stdout (default: human on stderr)
#   --help               show usage
#
# Surfaces checked:
#   1. Open GitHub issues (gh issue list --state open --search)
#   2. Local git worktrees (git worktree list)
#   3. Open GitHub PRs (gh pr list --state open) [unless --skip-remote]
#
# Matching heuristic (semantic title comparison):
#   - Tokenize title into significant words (lowercase, >=3 chars, alphanumeric+CJK)
#   - Match if >=2 shared significant tokens OR a shared CJK run >=3 chars
#   - "no file-shaped token" is a coverage gap, NOT a clean bill of health
#
# Exit: always 0 (advisory; never blocks creation).
#   Output levels:
#     OK no possible overlap found
#     WARNING N possible overlap(s) -- review before proceeding
#     INFO coverage gap -- matching is by token, not meaning
#
# Requires: `gh` with repo scope, `jq` (optional for --json).

set -eu

log() { printf 'check-duplicate-work: %s\n' "$*" >&2; }

usage() {
  sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
}

# --- Args ---
TITLE=""
REPOSITORY=""
SKIP_REMOTE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)       TITLE="$2"; shift 2 ;;
    --repository)  REPOSITORY="$2"; shift 2 ;;
    --skip-remote) SKIP_REMOTE=true; shift ;;
    --json)        JSON_OUTPUT=true; shift ;;
    --help|-h)     usage; exit 0 ;;
    *)             log "unknown arg: $1"; usage; exit 0 ;;
  esac
done

if [[ -z "$TITLE" ]]; then
  log "Error: --title is required"
  usage
  exit 0  # advisory; still exit 0
fi

# --- Resolve repository ---
if [[ -z "$REPOSITORY" ]]; then
  REPOSITORY=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
fi
if [[ -z "$REPOSITORY" ]]; then
  log "Warning: could not auto-detect repository; use --repository OWNER/REPO"
fi

# --- Tokenize title ---
# Significant tokens: lowercase, >=3 chars, alphanumeric only (strip punctuation)
# CJK runs: sequences of CJK characters >=3 chars are also tokens
tokenize() {
  local text="$1"
  # Lowercase
  text=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  # Extract alphanumeric tokens >=3 chars
  printf '%s' "$text" | grep -oE '[a-z0-9]{3,}' 2>/dev/null || true
  # Extract CJK runs >=3 chars (LC_ALL=C for byte-level matching — locale-independent)
  printf '%s' "$text" | LC_ALL=C grep -oE '[一-鿿]{3,}' 2>/dev/null || true
}

# Bash 3.2-compatible array from command output
array_from_cmd() {
  local outvar="$1"; shift
  eval "$outvar=()"
  while IFS= read -r line; do
    eval "$outvar+=(\"\$line\")"
  done
}

# Read title tokens into array
array_from_cmd TITLE_TOKENS < <(tokenize "$TITLE")

if [[ ${#TITLE_TOKENS[@]} -eq 0 ]]; then
  # No file-shaped tokens -- coverage gap
  if [[ "$JSON_OUTPUT" == true ]]; then
    printf '{"status":"coverage_gap","message":"no file-shaped token; matching is by token, not meaning","overlaps":[]}\n'
  else
    log "INFO no file-shaped token -- matching is by token, not meaning (coverage gap, not a clean bill)"
  fi
  exit 0
fi

# Inline shared-token counting (bash 3.2 safe)
count_shared_tokens() {
  # $1 = title tokens (space-separated), $2 = candidate tokens (space-separated)
  local title_toks="$1"
  local cand_toks="$2"
  local shared=0
  local tt
  for tt in $title_toks; do
    local ct
    for ct in $cand_toks; do
      if [[ "$tt" == "$ct" ]]; then
        shared=$((shared + 1))
        break
      fi
    done
  done
  echo "$shared"
}

# Convert title tokens array to space-separated string for count_shared_tokens
TITLE_TOKS_STR=""
for t in "${TITLE_TOKENS[@]}"; do
  TITLE_TOKS_STR="$TITLE_TOKS_STR $t"
done

# --- Surface 1: Open GitHub issues ---
ISSUE_OVERLAPS=()
if [[ -n "$REPOSITORY" ]]; then
  SEARCH_QUERY=""
  for token in "${TITLE_TOKENS[@]}"; do
    if [[ -n "$SEARCH_QUERY" ]]; then
      SEARCH_QUERY="$SEARCH_QUERY "
    fi
    SEARCH_QUERY="${SEARCH_QUERY}${token}"
  done

  ISSUES_JSON=$(gh issue list --repo "$REPOSITORY" --state open --search "$SEARCH_QUERY" --json number,title,url --limit 30 2>/dev/null || echo "[]")

  if [[ "$ISSUES_JSON" != "[]" && -n "$ISSUES_JSON" ]]; then
    while IFS= read -r line; do
      ISSUE_NUM=$(printf '%s' "$line" | jq -r '.number // empty' 2>/dev/null || echo "")
      ISSUE_TITLE=$(printf '%s' "$line" | jq -r '.title // empty' 2>/dev/null || echo "")
      ISSUE_URL=$(printf '%s' "$line" | jq -r '.url // empty' 2>/dev/null || echo "")

      [[ -z "$ISSUE_NUM" ]] && continue

      # Tokenize candidate title
      ISSUE_TOKS_STR=""
      while IFS= read -r tok; do
        ISSUE_TOKS_STR="$ISSUE_TOKS_STR $tok"
      done < <(tokenize "$ISSUE_TITLE")

      SHARED=$(count_shared_tokens "$TITLE_TOKS_STR" "$ISSUE_TOKS_STR")

      if [[ $SHARED -ge 2 ]]; then
        ISSUE_OVERLAPS+=("{\"number\":$ISSUE_NUM,\"title\":\"$ISSUE_TITLE\",\"url\":\"$ISSUE_URL\",\"shared_tokens\":$SHARED,\"surface\":\"open-issues\"}")
      fi
    done < <(printf '%s' "$ISSUES_JSON" | jq -c '.[]' 2>/dev/null || true)
  fi
fi

# --- Surface 2: Local git worktrees ---
WORKTREE_OVERLAPS=()
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -n "$REPO_ROOT" ]]; then
  while IFS= read -r wt_line; do
    [[ -z "$wt_line" ]] && continue
    WT_PATH=$(printf '%s' "$wt_line" | awk '{print $1}')
    WT_BRANCH=$(printf '%s' "$wt_line" | awk '{print $NF}' | tr -d '[]')

    # Tokenize branch name
    WT_TOKS_STR=""
    while IFS= read -r tok; do
      WT_TOKS_STR="$WT_TOKS_STR $tok"
    done < <(tokenize "$WT_BRANCH")

    # Also check title tokens in worktree path
    PATH_SHARED=0
    for tt in "${TITLE_TOKENS[@]}"; do
      if [[ "$WT_PATH" == *"$tt"* ]]; then
        PATH_SHARED=$((PATH_SHARED + 1))
      fi
    done

    SHARED=$(count_shared_tokens "$TITLE_TOKS_STR" "$WT_TOKS_STR")
    SHARED=$((SHARED + PATH_SHARED))

    if [[ $SHARED -ge 2 ]]; then
      WORKTREE_OVERLAPS+=("{\"branch\":\"$WT_BRANCH\",\"path\":\"$WT_PATH\",\"shared_tokens\":$SHARED,\"surface\":\"worktrees\"}")
    fi
  done < <(git worktree list 2>/dev/null || true)
fi

# --- Surface 3: Open GitHub PRs (unless --skip-remote) ---
PR_OVERLAPS=()
if [[ "$SKIP_REMOTE" == false && -n "$REPOSITORY" ]]; then
  PRS_JSON=$(gh pr list --repo "$REPOSITORY" --state open --json number,title,url --limit 30 2>/dev/null || echo "[]")

  if [[ "$PRS_JSON" != "[]" && -n "$PRS_JSON" ]]; then
    while IFS= read -r line; do
      PR_NUM=$(printf '%s' "$line" | jq -r '.number // empty' 2>/dev/null || echo "")
      PR_TITLE=$(printf '%s' "$line" | jq -r '.title // empty' 2>/dev/null || echo "")
      PR_URL=$(printf '%s' "$line" | jq -r '.url // empty' 2>/dev/null || echo "")

      [[ -z "$PR_NUM" ]] && continue

      PR_TOKS_STR=""
      while IFS= read -r tok; do
        PR_TOKS_STR="$PR_TOKS_STR $tok"
      done < <(tokenize "$PR_TITLE")

      SHARED=$(count_shared_tokens "$TITLE_TOKS_STR" "$PR_TOKS_STR")

      if [[ $SHARED -ge 2 ]]; then
        PR_OVERLAPS+=("{\"number\":$PR_NUM,\"title\":\"$PR_TITLE\",\"url\":\"$PR_URL\",\"shared_tokens\":$SHARED,\"surface\":\"open-prs\"}")
      fi
    done < <(printf '%s' "$PRS_JSON" | jq -c '.[]' 2>/dev/null || true)
  fi
fi

# --- Aggregate + report ---
TOTAL_OVERLAPS=$(( ${#ISSUE_OVERLAPS[@]} + ${#WORKTREE_OVERLAPS[@]} + ${#PR_OVERLAPS[@]} ))

if [[ "$JSON_OUTPUT" == true ]]; then
  printf '{"status":"'
  if [[ $TOTAL_OVERLAPS -eq 0 ]]; then
    printf 'clean'
  else
    printf 'overlap'
  fi
  printf '","total_overlaps":%d,"issues":[%s],"worktrees":[%s],"prs":[%s]}\n' \
    "$TOTAL_OVERLAPS" \
    "$(IFS=,; printf '%s' "${ISSUE_OVERLAPS[*]:-}")" \
    "$(IFS=,; printf '%s' "${WORKTREE_OVERLAPS[*]:-}")" \
    "$(IFS=,; printf '%s' "${PR_OVERLAPS[*]:-}")"
else
  if [[ $TOTAL_OVERLAPS -eq 0 ]]; then
    log "OK no possible overlap found (3 surfaces checked)"
  else
    log "WARNING $TOTAL_OVERLAPS possible overlap(s) -- review before proceeding:"
    if [[ ${#ISSUE_OVERLAPS[@]} -gt 0 ]]; then
      for o in "${ISSUE_OVERLAPS[@]}"; do
        NUM=$(printf '%s' "$o" | jq -r '.number')
        TIT=$(printf '%s' "$o" | jq -r '.title')
        log "  issue #$NUM: $TIT"
      done
    fi
    if [[ ${#WORKTREE_OVERLAPS[@]} -gt 0 ]]; then
      for o in "${WORKTREE_OVERLAPS[@]}"; do
        BR=$(printf '%s' "$o" | jq -r '.branch')
        log "  worktree: $BR"
      done
    fi
    if [[ ${#PR_OVERLAPS[@]} -gt 0 ]]; then
      for o in "${PR_OVERLAPS[@]}"; do
        NUM=$(printf '%s' "$o" | jq -r '.number')
        TIT=$(printf '%s' "$o" | jq -r '.title')
        log "  PR #$NUM: $TIT"
      done
    fi
  fi
fi

exit 0  # always advisory
