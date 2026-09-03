#!/usr/bin/env bash
# Returns JSON with repo context needed for PR creation in a single call.
# Usage: bash "$SKILL_ROOT/scripts/check-pr-context.sh" (absolute active skill root)
# Output: {"repo":"...","visibility":"PUBLIC|PRIVATE|INTERNAL|UNKNOWN","branch":"...","already_pushed":bool,"default_branch":"...","default_branch_source":"github|fallback",...,"uncommitted_count":N}
# default_branch falls back to "main" when the GitHub lookup fails; the
# fallback is surfaced via default_branch_source plus a stderr warning.

# `git config --get remote.origin.url` is read-only — it reads the remote without
# any chance of mutating it (unlike `git remote ...`, which can rewrite remotes).
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq not found on PATH"}' >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo '{"error":"gh not found on PATH"}' >&2
  exit 1
fi

REPO_FULL=$(git config --get remote.origin.url 2>/dev/null | sed -E 's|^.*github\.com[:/]||; s|\.git$||') || REPO_FULL=""

VISIBILITY=$(gh repo view --json visibility -q '.visibility' 2>/dev/null || echo "UNKNOWN")

BRANCH=$(git branch --show-current 2>/dev/null || echo "")

# ls-remote patterns tail-match path components (branch "foo" would match
# "bar/foo"), so query the fully qualified ref and require an exact match.
ALREADY_PUSHED="false"
if [ -n "$BRANCH" ] && git ls-remote --heads origin "refs/heads/$BRANCH" 2>/dev/null \
    | awk -v ref="refs/heads/$BRANCH" '$2==ref {found=1} END {exit !found}'; then
  ALREADY_PUSHED="true"
fi

# Uncommitted-changes count, EXCLUDING the intentional batch-work marker.
# `.lattice/.batch-work-active` is deliberately untracked-and-dirty for the whole
# batch run (its dirt visibility guards cleanup; never gitignore it), so it must
# not trip the "you have uncommitted changes" warning on every PR. Warning-level
# whitelist only — the marker still shows in `git status`.
UNCOMMITTED_COUNT=0
STATUS_LINES=$(git status --porcelain 2>/dev/null || true)
if [ -n "$STATUS_LINES" ]; then
  # Porcelain paths are repo-root-relative; match the marker path exactly
  # (including as a rename target) so real dirt is never masked.
  UNCOMMITTED_COUNT=$(printf '%s\n' "$STATUS_LINES" \
    | grep -cvE '^.. (\.lattice/\.batch-work-active|.* -> \.lattice/\.batch-work-active)$' || true)
fi
if [ "$UNCOMMITTED_COUNT" -gt 0 ]; then
  echo "Warning: $UNCOMMITTED_COUNT uncommitted change(s) besides the batch marker — commit or stash before the PR" >&2
fi

DEFAULT_BRANCH_SOURCE="github"
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null) || DEFAULT_BRANCH=""
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
  DEFAULT_BRANCH_SOURCE="fallback"
  echo "Warning: could not resolve the default branch from GitHub; assuming main" >&2
fi

# Integration-branch recommendation: fork-point infer the base the
# current branch forked from, so create-pr can pass --base <recommended_base>
# instead of blindly default_branch. resolve-integration-branch.sh lives in
# _lattice-lib (sibling of create-pr).
RIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lattice-lib/scripts" && pwd)/resolve-integration-branch.sh"
RECOMMENDED_BASE=""
RECOMMENDED_SOURCE=""
# Must stay valid JSON: it is passed to jq --argjson below, which aborts the
# whole context contract on an empty string when the resolver is missing.
LONG_LIVED="[]"
ASK_INTEGRATION="false"
if [[ -f "$RIB" ]]; then
  RIB_JSON=$(bash "$RIB" --repo-root "$PWD" --head "$BRANCH" --json 2>/dev/null || true)
  if [[ -n "$RIB_JSON" ]]; then
    RECOMMENDED_BASE=$(printf '%s' "$RIB_JSON" | jq -r '.recommended_base // ""' 2>/dev/null || true)
    RECOMMENDED_SOURCE=$(printf '%s' "$RIB_JSON" | jq -r '.base_source // ""' 2>/dev/null || true)
    LONG_LIVED=$(printf '%s' "$RIB_JSON" | jq -c '.long_lived // []' 2>/dev/null || true)
    [[ -n "$LONG_LIVED" ]] || LONG_LIVED="[]"
    ASK_INTEGRATION=$(printf '%s' "$RIB_JSON" | jq -r '.ask // false' 2>/dev/null || true)
  fi
fi

jq -nc \
  --arg repo "$REPO_FULL" \
  --arg visibility "$VISIBILITY" \
  --arg branch "$BRANCH" \
  --argjson already_pushed "$ALREADY_PUSHED" \
  --arg default_branch "$DEFAULT_BRANCH" \
  --arg default_branch_source "$DEFAULT_BRANCH_SOURCE" \
  --arg recommended_base "$RECOMMENDED_BASE" \
  --arg recommended_source "$RECOMMENDED_SOURCE" \
  --argjson long_lived "$LONG_LIVED" \
  --argjson ask_integration "$ASK_INTEGRATION" \
  --argjson uncommitted_count "$UNCOMMITTED_COUNT" \
  '{repo:$repo,visibility:$visibility,branch:$branch,already_pushed:$already_pushed,default_branch:$default_branch,default_branch_source:$default_branch_source,recommended_base:$recommended_base,recommended_source:$recommended_source,long_lived:$long_lived,ask_integration:$ask_integration,uncommitted_count:$uncommitted_count}'
