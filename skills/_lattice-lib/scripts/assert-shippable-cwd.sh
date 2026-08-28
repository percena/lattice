#!/usr/bin/env bash
# Refuse shippable Spec / ticket binder / product writes from the team-base checkout.
#
# Agents should run this (or ensure-workspace + cd into worktree) before writing
# Specs, ticket binders, or product code intended for a PR.
# create-review is exempt: .lattice/reviews/ may be written on team base.
#
# Fail when:
#   show-toplevel == MAIN_ROOT  AND  current branch is a team base
#   (main | master | dev | origin/HEAD default)
#   OR (strict profile only) show-toplevel == MAIN_ROOT  AND  on a non-base
#   branch — a plain feature branch in the main clone is the recorded drift
#   path (strict-profile-sibling-worktree-default memory); strict blocks it so
#   worktree-vs-branch is machine-enforced, not self-enforced. light profile
#   keeps the legacy pass (non-base branch on main clone is a valid escape).
#
# Pass when:
#   - inside a linked worktree (show-toplevel != MAIN_ROOT), or
#   - on a non-base branch on the main clone under LIGHT profile (--mode branch
#     escape hatch), or
#   - explicitly authorized via --allow-base-write --reason (covers base AND
#     strict non-base-on-main-clone; requires a clean tree + a reason).
#
# Explicit user-authorized base-direct escape:
#   --allow-base-write --reason <why>
# It requires a named base branch and a clean starting tree; JSON records it.
#
# Usage: assert-shippable-cwd.sh [--json] [--base <name>] [--allow-base-write --reason <why>]
# Exit: 0 ok, 1 on team base, 2 usage / not a git repo
set -euo pipefail

AS_JSON=false
BASE_OVERRIDE=""
ALLOW_BASE_WRITE=false
ESCAPE_REASON=""

usage() {
  cat >&2 <<'EOF'
Usage: assert-shippable-cwd.sh [--json] [--base <branch>] [--allow-base-write --reason <why>]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --base) BASE_OVERRIDE="${2:-}"; shift 2 ;;
    --allow-base-write) ALLOW_BASE_WRITE=true; shift ;;
    --reason) ESCAPE_REASON="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

# --json renders via python3: preflight before any checks so a passing check
# cannot still exit 127 at emission time (style matches ensure-workspace.sh).
if $AS_JSON && ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required by assert-shippable-cwd.sh --json" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git work tree" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lattice-home.sh"

REPO_ROOT=$(git rev-parse --show-toplevel)
MAIN_ROOT=$(lattice_main_root || echo "$REPO_ROOT")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
# Detached HEAD reports "HEAD" — treat as empty for base checks.
[[ "$BRANCH" == "HEAD" ]] && BRANCH=""

# Profile (strict default | light). Under strict, a non-base branch on the
# main clone is non-shippable (forces worktree); light keeps the legacy pass.
PROFILE="strict"
if command -v lattice_profile >/dev/null 2>&1; then
  PROFILE=$(lattice_profile 2>/dev/null || echo "strict")
elif [[ -n "${LATTICE_PROFILE:-}" ]]; then
  PROFILE=$(printf '%s' "${LATTICE_PROFILE}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
fi
case "$PROFILE" in light|strict) ;; *) PROFILE="strict" ;; esac

DEFAULT_BASE=""
BASE_SOURCE=""
if [[ -n "$BASE_OVERRIDE" ]]; then
  DEFAULT_BASE="$BASE_OVERRIDE"
  BASE_SOURCE="explicit"
else
  if [[ -f "$REPO_ROOT/.lattice/config.yaml" ]]; then
    DEFAULT_BASE=$(grep -E '^[[:space:]]*base_branch:[[:space:]]*' "$REPO_ROOT/.lattice/config.yaml" 2>/dev/null | head -1 | sed -E 's/^[[:space:]]*base_branch:[[:space:]]*//; s/[[:space:]]*[#].*$//; s/["'\'']//g' | tr -d '[:space:]' || true)
    [[ -n "$DEFAULT_BASE" ]] && BASE_SOURCE="config"
  fi
  if [[ -z "$DEFAULT_BASE" ]] && command -v gh >/dev/null 2>&1; then
    DEFAULT_BASE=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)
    [[ -n "$DEFAULT_BASE" ]] && BASE_SOURCE="gh-default"
  fi
  if [[ -z "$DEFAULT_BASE" ]]; then
    DEFAULT_BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
    [[ -n "$DEFAULT_BASE" ]] && BASE_SOURCE="origin-HEAD"
  fi
fi
if [[ -z "$DEFAULT_BASE" ]]; then
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/remotes/origin/$candidate" 2>/dev/null || git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
      DEFAULT_BASE="$candidate"
      BASE_SOURCE="fallback"
      break
    fi
  done
fi
[[ -z "$DEFAULT_BASE" ]] && DEFAULT_BASE="main" && BASE_SOURCE="fallback"

DEFAULT_BASE_NAME="$DEFAULT_BASE"
DEFAULT_BASE_NAME="${DEFAULT_BASE_NAME#refs/remotes/origin/}"
DEFAULT_BASE_NAME="${DEFAULT_BASE_NAME#refs/heads/}"
DEFAULT_BASE_NAME="${DEFAULT_BASE_NAME#origin/}"

is_base=false
case "$BRANCH" in
  main|master|dev|"$DEFAULT_BASE_NAME") is_base=true ;;
esac
# Empty branch (detached / unborn) on the main clone is also non-shippable.
if [[ -z "$BRANCH" ]]; then
  is_base=true
fi

on_main_clone=false
if [[ "$REPO_ROOT" == "$MAIN_ROOT" ]]; then
  on_main_clone=true
fi

OK=true
REASON="ok"
if $on_main_clone && $is_base; then
  OK=false
  if [[ -z "$BRANCH" ]]; then
    REASON="detached_or_empty_on_main_clone"
  else
    REASON="team_base_checkout"
  fi
fi

# Strict profile: a non-base branch on the main clone is non-shippable (the
# recorded drift path). Light profile keeps the legacy pass.
NONBASE_ON_MAIN=false
if $on_main_clone && ! $is_base && [[ -n "$BRANCH" ]] && [[ "$PROFILE" == "strict" ]]; then
  NONBASE_ON_MAIN=true
  OK=false
  REASON="non_base_on_main_clone"
fi

# Preserve the physical checkout/branch fact before an authorized escape changes
# REASON. Consumers use this field for audit reporting, not only pass/fail.
ON_TEAM_BASE=false
if $on_main_clone && $is_base; then
  ON_TEAM_BASE=true
fi

BASE_ESCAPE=false
if ! $OK && $ALLOW_BASE_WRITE; then
  if [[ -z "$ESCAPE_REASON" ]]; then
    echo "Error: --allow-base-write requires --reason and explicit user authorization" >&2
    exit 2
  fi
  if [[ -z "$BRANCH" ]]; then
    echo "Error: base-direct escape is not allowed on detached or empty HEAD" >&2
    exit 1
  fi
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "Error: base-direct escape requires a clean starting tree" >&2
    exit 1
  fi
  OK=true
  if $NONBASE_ON_MAIN; then
    REASON="authorized_nonbase_direct"
  else
    REASON="authorized_base_direct"
  fi
  BASE_ESCAPE=true
fi

emit() {
  if $AS_JSON; then
    python3 - "$OK" "$REASON" "$REPO_ROOT" "$MAIN_ROOT" "$BRANCH" "$DEFAULT_BASE" "$BASE_SOURCE" "$BASE_ESCAPE" "$ESCAPE_REASON" "$ON_TEAM_BASE" <<'PY'
import json, sys
ok, reason, repo, main, branch, base, base_source, escaped, escape_reason, on_team_base = sys.argv[1:11]
print(json.dumps({
  "ok": ok == "true",
  "reason": reason,
  "repo_root": repo,
  "main_root": main,
  "branch": branch or None,
  "default_base": base,
  "base_source": base_source,
  "on_main_clone": repo == main,
  "on_team_base": on_team_base == "true",
  "base_direct_escape": escaped == "true",
  "escape_reason": escape_reason or None,
  "cd_hint": None if ok == "true" else (
    "Open a bound worktree first: "
    "bash …/ensure-workspace.sh --mode worktree --bind tkt|spc --id N --slug … "
    "then cd to the returned path before any L0/product Write."
  ),
}, indent=2))
PY
  else
    if $OK; then
      echo "assert-shippable-cwd: ok"
      echo "  repo:   $REPO_ROOT"
      echo "  branch: ${BRANCH:-detached}"
      if $BASE_ESCAPE; then
        echo "  escape: user-authorized base-direct ($ESCAPE_REASON)"
      fi
    else
      echo "assert-shippable-cwd: FAIL — shippable writes blocked on team-base checkout" >&2
      echo "  repo:   $REPO_ROOT" >&2
      echo "  main:   $MAIN_ROOT" >&2
      echo "  branch: ${BRANCH:-detached/empty} ($REASON)" >&2
      echo "  fix:    ensure-workspace --mode worktree --bind tkt|spc --id N --slug …" >&2
      echo "          then cd into the worktree path before binders/Specs/lineage/code" >&2
    fi
  fi
}

emit
if $OK; then
  exit 0
fi
exit 1
