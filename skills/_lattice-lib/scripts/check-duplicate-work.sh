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
# Exit: always 0 (advisory; never blocks creation — even with missing deps).
#   Output levels:
#     OK no possible overlap found
#     WARNING N possible overlap(s) -- review before proceeding
#     INCONCLUSIVE N coverage gap(s) -- one or more surfaces did not run
#     INFO coverage gap -- matching is by token, not meaning
#   A missing dependency or failed query never silently narrows the check:
#   each affected surface reports "coverage gap: <surface> unavailable (<reason>)"
#   and the verdict says OK only when every surface actually ran.
#
# Requires: `gh` with repo scope, `jq` (JSON parsing and overlap-record
# construction), `python3` (CJK run comparison; already a dependency of
# sibling lib scripts). Missing deps degrade to coverage gaps, not to "OK".

set -euo pipefail

log() { printf 'check-duplicate-work: %s\n' "$*" >&2; }

usage() {
  sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'
}

# --- Args ---
TITLE=""
REPOSITORY=""
SKIP_REMOTE=false
JSON_OUTPUT=false

# Advisory contract: an option missing its value prints the usage and still
# exits 0 (never an unbound-variable death).
need_value() {
  # $1 = option name, $2 = remaining positional count at the option
  if [[ "$2" -lt 2 ]]; then
    log "Error: $1 requires a value"
    usage
    exit 0 # advisory; still exit 0
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)       need_value --title "$#"; TITLE="${2:-}"; shift 2 ;;
    --repository)  need_value --repository "$#"; REPOSITORY="${2:-}"; shift 2 ;;
    --skip-remote) SKIP_REMOTE=true; shift ;;
    --json)        JSON_OUTPUT=true; shift ;;
    --help|-h)     usage; exit 0 ;;
    *)             log "unknown arg: $1"; usage; exit 0 ;;
  esac
done

if [[ -z "$TITLE" ]]; then
  log "Error: --title is required"
  usage
  exit 0 # advisory; still exit 0
fi

# --- Dependency preflight (fail loud, not open) ---
# A missing dependency never aborts (advisory contract), but every surface
# that needs it becomes an explicit coverage gap instead of a silent empty
# result -- the verdict must not claim a clean bill of health it cannot back.
HAVE_GH=true
command -v gh >/dev/null 2>&1 || HAVE_GH=false
HAVE_JQ=true
command -v jq >/dev/null 2>&1 || HAVE_JQ=false
HAVE_PYTHON3=true
command -v python3 >/dev/null 2>&1 || HAVE_PYTHON3=false

COVERAGE_GAPS=()
add_gap() { COVERAGE_GAPS+=("$1"); }

# gh `list` caps results but surfaces no has-more flag. A high limit keeps the
# common case complete; when the returned count equals the limit the surface
# may be silently truncated (a duplicate as the 201st match is never seen),
# so a coverage gap is reported rather than a clean "OK" verdict that
# contradicts the header contract ("a missing/failed query never silently
# narrows the check"). tkt-242 L1.
LIST_LIMIT="${CDW_LIST_LIMIT:-200}"

# --- Resolve repository ---
if [[ -z "$REPOSITORY" && "$HAVE_GH" == true ]]; then
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

# True when the string contains CJK bytes (same byte-level class as tokenize).
has_cjk() { printf '%s' "$1" | LC_ALL=C grep -q '[一-鿿]'; }

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

# --- CJK run comparison (the OR branch of the match heuristic) ---
# Two titles also match when their CJK runs share a substring of >=3
# characters (character count, not bytes -- hence python3, which sibling lib
# scripts already embed). Pure-ASCII inputs return before any python3 spawn,
# so ASCII-only behavior is byte-for-byte unchanged.
cjk_shared_run() {
  # $1 = title tokens, $2 = candidate tokens (space-separated; tokenize()
  # emits each CJK run >=3 chars as a single token)
  has_cjk "$1" || return 1
  has_cjk "$2" || return 1
  [[ "$HAVE_PYTHON3" == true ]] || return 1
  python3 - "$1" "$2" <<'PY'
import sys

def trigrams(toks):
    runs = [t for t in toks.split() if any('一' <= c <= '鿿' for c in t)]
    return {r[i:i + 3] for r in runs for i in range(len(r) - 2)}

# Any shared CJK substring >=3 chars implies a shared 3-char substring.
sys.exit(0 if trigrams(sys.argv[1]) & trigrams(sys.argv[2]) else 1)
PY
}

# Convert title tokens array to space-separated string for count_shared_tokens
TITLE_TOKS_STR=""
for t in "${TITLE_TOKENS[@]}"; do
  TITLE_TOKS_STR="$TITLE_TOKS_STR $t"
done

# CJK titles need python3 for the OR branch; say so instead of silently
# falling back to token-only matching.
if [[ "$HAVE_PYTHON3" == false ]] && has_cjk "$TITLE_TOKS_STR"; then
  add_gap "cjk-matching unavailable (python3 missing)"
fi

# --- Surface 1: Open GitHub issues ---
ISSUE_OVERLAPS=()
ISSUES_RAN=false
if [[ "$HAVE_GH" == false ]]; then
  add_gap "open-issues unavailable (gh missing)"
elif [[ "$HAVE_JQ" == false ]]; then
  add_gap "open-issues unavailable (jq missing)"
elif [[ -z "$REPOSITORY" ]]; then
  add_gap "open-issues unavailable (repository unknown)"
else
  SEARCH_QUERY=""
  for token in "${TITLE_TOKENS[@]}"; do
    if [[ -n "$SEARCH_QUERY" ]]; then
      SEARCH_QUERY="$SEARCH_QUERY "
    fi
    SEARCH_QUERY="${SEARCH_QUERY}${token}"
  done

  if ! ISSUES_JSON=$(gh issue list --repo "$REPOSITORY" --state open --search "$SEARCH_QUERY" --json number,title,url --limit "$LIST_LIMIT" 2>/dev/null); then
    add_gap "open-issues unavailable (gh issue list failed)"
  elif ! ISSUE_LINES=$(printf '%s' "$ISSUES_JSON" | jq -c '.[]?' 2>/dev/null); then
    add_gap "open-issues unavailable (unparseable gh issue list output)"
  else
    ISSUES_RAN=true
    # gh surfaces no has-more flag; a result count equal to the limit means the
    # surface may be truncated. Report a coverage gap so the verdict is not a
    # silent "OK" that an unseen older duplicate contradicts (tkt-242 L1).
    ISSUE_COUNT=$(printf '%s' "$ISSUES_JSON" | jq 'length' 2>/dev/null || echo 0)
    [[ "$ISSUE_COUNT" -eq "$LIST_LIMIT" ]] && \
      add_gap "open-issues truncated (returned $ISSUE_COUNT == limit; older matches may be hidden)"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ISSUE_NUM=$(printf '%s' "$line" | jq -r '.number // empty' 2>/dev/null || echo "")
      ISSUE_TITLE=$(printf '%s' "$line" | jq -r '.title // empty' 2>/dev/null || echo "")
      ISSUE_URL=$(printf '%s' "$line" | jq -r '.url // empty' 2>/dev/null || echo "")

      # numeric guard: a non-numeric .number (gh wrapper/schema drift) must not
      # reach `jq --argjson` — under set -e that kills the script and breaks the
      # advisory exit-0 contract (pre-merge review of pr-99).
      [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]] || continue

      # Tokenize candidate title
      ISSUE_TOKS_STR=""
      while IFS= read -r tok; do
        ISSUE_TOKS_STR="$ISSUE_TOKS_STR $tok"
      done < <(tokenize "$ISSUE_TITLE")

      SHARED=$(count_shared_tokens "$TITLE_TOKS_STR" "$ISSUE_TOKS_STR")

      if [[ $SHARED -ge 2 ]] || cjk_shared_run "$TITLE_TOKS_STR" "$ISSUE_TOKS_STR"; then
        ISSUE_OVERLAPS+=("$(jq -nc \
          --argjson number "$ISSUE_NUM" \
          --arg title "$ISSUE_TITLE" \
          --arg url "$ISSUE_URL" \
          --argjson shared_tokens "$SHARED" \
          --arg surface "open-issues" \
          '{number:$number,title:$title,url:$url,shared_tokens:$shared_tokens,surface:$surface}')")
      fi
    done <<<"$ISSUE_LINES"
  fi
fi

# --- Surface 2: Local git worktrees ---
WORKTREE_OVERLAPS=()
WORKTREES_RAN=false
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ "$HAVE_JQ" == false ]]; then
  # Overlap records are jq-built, so this surface needs jq too.
  add_gap "worktrees unavailable (jq missing)"
elif [[ -z "$REPO_ROOT" ]]; then
  add_gap "worktrees unavailable (not inside a git repository)"
elif ! WT_LIST=$(git worktree list 2>/dev/null); then
  add_gap "worktrees unavailable (git worktree list failed)"
else
  WORKTREES_RAN=true
  while IFS= read -r wt_line; do
    [[ -z "$wt_line" ]] && continue
    WT_PATH=$(printf '%s' "$wt_line" | awk '{print $1}')
    WT_BRANCH=$(printf '%s' "$wt_line" | awk '{print $NF}' | tr -d '[]')

    # Tokenize branch name
    WT_TOKS_STR=""
    while IFS= read -r tok; do
      WT_TOKS_STR="$WT_TOKS_STR $tok"
    done < <(tokenize "$WT_BRANCH")

    # Count title tokens found in either branch tokens or path substring (union, not sum —
    # a token that appears in both is counted once, preventing false positives from common
    # 3-letter words like "fix" matching in both the branch and the path).
    SHARED=0
    for tt in "${TITLE_TOKENS[@]}"; do
      found=false
      # Check branch tokens first
      for ct in $WT_TOKS_STR; do
        if [[ "$tt" == "$ct" ]]; then
          found=true
          break
        fi
      done
      # Check path substring only if not already matched in branch (union)
      if [[ "$found" == false && "$WT_PATH" == *"$tt"* ]]; then
        found=true
      fi
      if [[ "$found" == true ]]; then
        SHARED=$((SHARED + 1))
      fi
    done

    if [[ $SHARED -ge 2 ]] || cjk_shared_run "$TITLE_TOKS_STR" "$WT_TOKS_STR"; then
      WORKTREE_OVERLAPS+=("$(jq -nc \
        --arg branch "$WT_BRANCH" \
        --arg path "$WT_PATH" \
        --argjson shared_tokens "$SHARED" \
        --arg surface "worktrees" \
        '{branch:$branch,path:$path,shared_tokens:$shared_tokens,surface:$surface}')")
    fi
  done <<<"$WT_LIST"
fi

# --- Surface 3: Open GitHub PRs (unless --skip-remote) ---
PR_OVERLAPS=()
PRS_RAN=false
if [[ "$SKIP_REMOTE" == true ]]; then
  : # deliberately skipped by the caller; a skip is not a coverage gap
elif [[ "$HAVE_GH" == false ]]; then
  add_gap "open-prs unavailable (gh missing)"
elif [[ "$HAVE_JQ" == false ]]; then
  add_gap "open-prs unavailable (jq missing)"
elif [[ -z "$REPOSITORY" ]]; then
  add_gap "open-prs unavailable (repository unknown)"
elif ! PRS_JSON=$(gh pr list --repo "$REPOSITORY" --state open --json number,title,url --limit "$LIST_LIMIT" 2>/dev/null); then
  add_gap "open-prs unavailable (gh pr list failed)"
elif ! PR_LINES=$(printf '%s' "$PRS_JSON" | jq -c '.[]?' 2>/dev/null); then
  add_gap "open-prs unavailable (unparseable gh pr list output)"
else
  PRS_RAN=true
  # Same truncation guard as the issues surface (tkt-242 L1).
  PR_COUNT=$(printf '%s' "$PRS_JSON" | jq 'length' 2>/dev/null || echo 0)
  [[ "$PR_COUNT" -eq "$LIST_LIMIT" ]] && \
    add_gap "open-prs truncated (returned $PR_COUNT == limit; older matches may be hidden)"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    PR_NUM=$(printf '%s' "$line" | jq -r '.number // empty' 2>/dev/null || echo "")
    PR_TITLE=$(printf '%s' "$line" | jq -r '.title // empty' 2>/dev/null || echo "")
    PR_URL=$(printf '%s' "$line" | jq -r '.url // empty' 2>/dev/null || echo "")

    [[ "$PR_NUM" =~ ^[0-9]+$ ]] || continue

    PR_TOKS_STR=""
    while IFS= read -r tok; do
      PR_TOKS_STR="$PR_TOKS_STR $tok"
    done < <(tokenize "$PR_TITLE")

    SHARED=$(count_shared_tokens "$TITLE_TOKS_STR" "$PR_TOKS_STR")

    if [[ $SHARED -ge 2 ]] || cjk_shared_run "$TITLE_TOKS_STR" "$PR_TOKS_STR"; then
      PR_OVERLAPS+=("$(jq -nc \
        --argjson number "$PR_NUM" \
        --arg title "$PR_TITLE" \
        --arg url "$PR_URL" \
        --argjson shared_tokens "$SHARED" \
        --arg surface "open-prs" \
        '{number:$number,title:$title,url:$url,shared_tokens:$shared_tokens,surface:$surface}')")
    fi
  done <<<"$PR_LINES"
fi

# --- Aggregate + report ---
TOTAL_OVERLAPS=$(( ${#ISSUE_OVERLAPS[@]} + ${#WORKTREE_OVERLAPS[@]} + ${#PR_OVERLAPS[@]} ))
TOTAL_GAPS=${#COVERAGE_GAPS[@]}
SURFACES_CHECKED=0
if [[ "$ISSUES_RAN" == true ]]; then SURFACES_CHECKED=$((SURFACES_CHECKED + 1)); fi
if [[ "$WORKTREES_RAN" == true ]]; then SURFACES_CHECKED=$((SURFACES_CHECKED + 1)); fi
if [[ "$PRS_RAN" == true ]]; then SURFACES_CHECKED=$((SURFACES_CHECKED + 1)); fi

# Gap strings are controlled ASCII (no quotes/backslashes); safe to embed.
GAPS_JSON=""
if [[ $TOTAL_GAPS -gt 0 ]]; then
  for g in "${COVERAGE_GAPS[@]}"; do
    if [[ -n "$GAPS_JSON" ]]; then GAPS_JSON="$GAPS_JSON,"; fi
    GAPS_JSON="$GAPS_JSON\"$g\""
  done
fi

if [[ "$JSON_OUTPUT" == true ]]; then
  printf '{"status":"'
  if [[ $TOTAL_OVERLAPS -gt 0 ]]; then
    printf 'overlap'
  elif [[ $TOTAL_GAPS -gt 0 ]]; then
    printf 'coverage_gap'
  else
    printf 'clean'
  fi
  printf '","total_overlaps":%d,"surfaces_checked":%d,"coverage_gaps":[%s],"issues":[%s],"worktrees":[%s],"prs":[%s]}\n' \
    "$TOTAL_OVERLAPS" \
    "$SURFACES_CHECKED" \
    "$GAPS_JSON" \
    "$(IFS=,; printf '%s' "${ISSUE_OVERLAPS[*]:-}")" \
    "$(IFS=,; printf '%s' "${WORKTREE_OVERLAPS[*]:-}")" \
    "$(IFS=,; printf '%s' "${PR_OVERLAPS[*]:-}")"
else
  if [[ $TOTAL_GAPS -gt 0 ]]; then
    for g in "${COVERAGE_GAPS[@]}"; do
      log "coverage gap: $g"
    done
  fi
  if [[ $TOTAL_OVERLAPS -gt 0 ]]; then
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
  elif [[ $TOTAL_GAPS -gt 0 ]]; then
    log "INCONCLUSIVE $TOTAL_GAPS coverage gap(s) -- only $SURFACES_CHECKED surface(s) ran; NOT a clean bill of health"
  else
    log "OK no possible overlap found ($SURFACES_CHECKED surfaces checked)"
  fi
fi

exit 0 # always advisory
