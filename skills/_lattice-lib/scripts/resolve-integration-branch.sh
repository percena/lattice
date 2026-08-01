#!/usr/bin/env bash
# Resolve the integration branch a feature worktree should PR into.
#
# General rule (branch-model-agnostic):
#   PR base = the long-lived branch the worktree forked from
#           = the user's working branch at start-work time (when long-lived).
#
# Long-lived set (discovered per repo, never hardcoded names):
#   - GitHub default branch
#   - branches matching naming conventions: main, master, dev, develop,
#     release/*, rc/*  (config-overridable via long_lived_patterns)
#   - .lattice/config.yaml long_lived_patterns: [glob, ...]  (additive)
#   - (optional) gh branch-protection rules — opt-in via --with-protection
#
# Base resolution pipeline:
#   1. user_branch ∈ LL            → base = user_branch            (source: user_branch)
#   2. fork-point inference         → base = nearest LL by merge-base (source: fork_point)
#   3. ambiguous (≥2 LL tie / none reachable, |LL|≥2) → base = ""  (source: ask)
#      (|LL| == 1                  → base = LL[0]                  (source: only_choice))
#   4. LL empty                     → base = gh default             (source: default)
#
# Usage:
#   resolve-integration-branch.sh --repo-root <root>
#                                 [--user-branch <name>]   # main-checkout current
#                                 [--head <ref>]           # worktree HEAD for fork-point
#                                 [--with-protection]      # include gh branch-protection
#                                 [--json]
#   Exits 0 always (resolution is advisory). JSON on --json; human on default.
# Exit 2 on usage error.
set -euo pipefail

REPO_ROOT=""
USER_BRANCH=""
HEAD_REF=""
WITH_PROTECTION=false
AS_JSON=false

usage() {
  cat >&2 <<'EOF'
Usage: resolve-integration-branch.sh --repo-root <root>
       [--user-branch <name>] [--head <ref>] [--with-protection] [--json]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    --user-branch) USER_BRANCH="${2:-}"; shift 2 ;;
    --head) HEAD_REF="${2:-}"; shift 2 ;;
    --with-protection) WITH_PROTECTION=true; shift ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: --repo-root is required" >&2
  usage
fi
if ! cd "$REPO_ROOT" 2>/dev/null; then
  echo "Error: cannot cd to repo root: $REPO_ROOT" >&2
  exit 1
fi

# --- Long-lived discovery -----------------------------------------------------
DEFAULT_BRANCH=""
if command -v gh >/dev/null 2>&1; then
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)
fi
[[ -z "$DEFAULT_BRANCH" ]] && DEFAULT_BRANCH="main"

# Config-overridable naming patterns (additive to the defaults).
NAMING_PATTERNS=("main" "master" "dev" "develop")
# release/* and rc/* are glob-style matched against the short branch name.
EXTRA_GLOBS=("release/*" "rc/*")

CFG="$REPO_ROOT/.lattice/config.yaml"
if [[ -f "$CFG" ]]; then
  # Parse long_lived_patterns: inline [a, b] or next-line block (- item).
  cfg_extra=""
  if grep -qE '^[[:space:]]*long_lived_patterns:[[:space:]]*\[' "$CFG" 2>/dev/null; then
    cfg_extra=$(grep -E '^[[:space:]]*long_lived_patterns:' "$CFG" \
      | sed -E 's/^[[:space:]]*long_lived_patterns:[[:space:]]*//; s/^\[//; s/\][[:space:]]*$//; s/[[:space:]]*#.*$//' \
      | tr ',' '\n' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//' || true)
  else
    # Block form: lines indented under long_lived_patterns: starting with -
    cfg_extra=$(awk '
      /^[[:space:]]*long_lived_patterns:[[:space:]]*$/ {on=1; next}
      on && /^[[:space:]]*-/ {sub(/^[[:space:]]*-[[:space:]]*/,""); gsub(/[[:space:]]*#.*$/,""); gsub(/^["'\''"]|["'\''"]$/,""); print; next}
      on && !/^[[:space:]]*-/ && !/^[[:space:]]*$/ {on=0}
    ' "$CFG" 2>/dev/null || true)
  fi
  if [[ -n "$cfg_extra" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && EXTRA_GLOBS+=("$p")
    done <<< "$cfg_extra"
  fi
fi

# Gather origin's branches (short names). for-each-ref is porcelain and
# locale-independent, and it lets us drop the origin/HEAD symref explicitly.
# The previous `git branch -r | sed | grep` pipeline stripped everything after
# the first space BEFORE the grep, so the "HEAD ->" filter could never match
# and origin/HEAD produced a phantom long-lived branch named "HEAD"; it also
# let branches of OTHER remotes in under their own prefix.
REMOTE_BRANCHES=()
while IFS= read -r _rb; do
  [[ -n "$_rb" && "$_rb" != "HEAD" ]] && REMOTE_BRANCHES+=("$_rb")
done < <(
  git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin 2>/dev/null || true
)

# Match a short branch name against the naming sets.
matches_pattern() {
  local b="$1"
  for p in "${NAMING_PATTERNS[@]}"; do
    [[ "$b" == "$p" ]] && return 0
  done
  for g in "${EXTRA_GLOBS[@]}"; do
    # glob match: * -> shell wildcard via case (release/* matches release/1.0)
    # shellcheck disable=SC2254 # glob expansion is intentional here
    case "$b" in
      $g) return 0 ;;
    esac
  done
  return 1
}

# Build the long-lived set (unique, sorted).
LL_LIST=()
_ll_contains() {
  local needle="$1"
  [[ ${#LL_LIST[@]} -eq 0 ]] && return 1
  for x in "${LL_LIST[@]}"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}
add_ll() {
  local b="$1"
  [[ -z "$b" ]] && return
  if ! _ll_contains "$b"; then
    LL_LIST+=("$b")
  fi
}

add_ll "$DEFAULT_BRANCH"
for b in ${REMOTE_BRANCHES[@]+"${REMOTE_BRANCHES[@]}"}; do
  matches_pattern "$b" && add_ll "$b"
done

# Opt-in protection: protected branches are long-lived even if not name-matched.
if $WITH_PROTECTION && command -v gh >/dev/null 2>&1; then
  for b in ${REMOTE_BRANCHES[@]+"${REMOTE_BRANCHES[@]}"}; do
    _ll_contains "$b" && continue
    if gh api "repos/:owner/:repo/branches/$b/protection" >/dev/null 2>&1 \
       || gh api "repos/{owner}/{repo}/branches/$b/protection" >/dev/null 2>&1; then
      add_ll "$b"
    fi
  done
fi

LL_COUNT=${#LL_LIST[@]}

# --- Pipeline -----------------------------------------------------------------
RECOMMENDED=""
SOURCE="default"

if [[ -n "$USER_BRANCH" ]]; then
  for b in ${LL_LIST[@]+"${LL_LIST[@]}"}; do
    if [[ "$b" == "$USER_BRANCH" ]]; then
      RECOMMENDED="$USER_BRANCH"
      SOURCE="user_branch"
      break
    fi
  done
fi

if [[ -z "$RECOMMENDED" && -n "$HEAD_REF" ]]; then
  head_oid=$(git rev-parse --verify --quiet "${HEAD_REF}^{commit}" 2>/dev/null || true)
  if [[ -n "$head_oid" ]]; then
    # Among long-lived branches that are ANCESTORS of head (feature forked off
    # their line), pick the one with the fewest commits-ahead (closest fork).
    # Ties on ahead-count ⇒ ambiguous ⇒ ask. This correctly distinguishes
    # "forked from main" vs "forked from dev" even when they share a merge-base.
    best=""
    best_ahead=""
    for b in ${LL_LIST[@]+"${LL_LIST[@]}"}; do
      b_ref="refs/remotes/origin/$b"
      git rev-parse --verify --quiet "${b_ref}^{commit}" >/dev/null 2>&1 || b_ref="$b"
      # b must be an ancestor of head (feature is a descendant of b's line).
      git merge-base --is-ancestor "$b_ref" "$head_oid" 2>/dev/null || continue
      ahead=$(git rev-list --count "${b_ref}..${head_oid}" 2>/dev/null || echo "")
      [[ -z "$ahead" ]] && continue
      if [[ -z "$best_ahead" || "$ahead" -lt "$best_ahead" ]]; then
        best="$b"; best_ahead="$ahead"
      elif [[ "$ahead" == "$best_ahead" && "$b" != "$best" ]]; then
        best="AMBIGUOUS" # tie on ahead-count
      fi
    done
    if [[ -n "$best" && "$best" != "AMBIGUOUS" ]]; then
      RECOMMENDED="$best"; SOURCE="fork_point"
    fi
  fi
fi

if [[ -z "$RECOMMENDED" ]]; then
  if [[ "$LL_COUNT" -eq 1 ]]; then
    RECOMMENDED="${LL_LIST[0]}"; SOURCE="only_choice"
  elif [[ "$LL_COUNT" -ge 2 ]]; then
    RECOMMENDED=""; SOURCE="ask"
  else
    RECOMMENDED="$DEFAULT_BRANCH"; SOURCE="default"
  fi
fi

# --- Output -------------------------------------------------------------------
if $AS_JSON; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required by resolve-integration-branch.sh --json" >&2
    exit 1
  fi
  ll_json=$(printf '%s\n' ${LL_LIST[@]+"${LL_LIST[@]}"} | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines() if sys.stdin else []))' 2>/dev/null || echo "[]")
  python3 - "$RECOMMENDED" "$SOURCE" "$DEFAULT_BRANCH" "$USER_BRANCH" "$HEAD_REF" "$LL_COUNT" "$ll_json" <<'PY'
import json, sys
rec, src, default, ub, head, lc, ll = sys.argv[1:8]
print(json.dumps({
  "ok": True,
  "recommended_base": rec,
  "base_source": src,
  "default_branch": default,
  "user_branch": ub or None,
  "head": head or None,
  "long_lived": json.loads(ll),
  "long_lived_count": int(lc),
  "ask": src == "ask",
}, indent=2))
PY
else
  echo "resolve-integration-branch:"
  echo "  default_branch: $DEFAULT_BRANCH"
  echo "  long_lived: ${LL_LIST[*]}"
  echo "  user_branch: ${USER_BRANCH:-(unset)}"
  echo "  head: ${HEAD_REF:-(unset)}"
  echo "  recommended_base: ${RECOMMENDED:-(ASK)}"
  echo "  base_source: $SOURCE"
fi
exit 0
