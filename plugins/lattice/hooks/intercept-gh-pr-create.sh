#!/usr/bin/env bash
# PreToolUse: advise on bare `gh pr create` unless create-pr is active.
# LATTICE_HOOK_MODE=strict blocks instead of advising.
# Thin entry: skill-specific config only; the shared flow (pre-filter, strip,
# marker check, rewind re-validation, advisory/strict delivery) lives in
# lib/intercept-gh-pr-common.sh. Fail OPEN on ambiguity, including a missing lib.

# shellcheck disable=SC2034  # consumed by lib/intercept-gh-pr-common.sh
INTERCEPT_SKILL_NAME="create-pr"
INTERCEPT_GH_PR_VERB='create'
INTERCEPT_SYSTEM_MESSAGE="lattice: bare gh pr create noticed — /create-pr is the recommended path (advisory)"
INTERCEPT_ADVICE='⚠️ Direct gh pr create detected. The create-pr skill is the recommended path, not a mandatory one.

Use: Skill(skill: "lattice:create-pr")
  or: /create-pr

The create-pr skill ensures proper PR descriptions by:
- Extracting intent from the session (asks if missing)
- Following the Why/How format standard
- Creating meaningful documentation'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HOOK_DIR}/lib/intercept-gh-pr-common.sh" 2>/dev/null || exit 0
intercept_gh_pr_main
