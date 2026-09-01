#!/usr/bin/env bash
# PreToolUse: block bare `gh issue create` unless create-tickets is active.
# Default mode is strict (blocks). Set LATTICE_HOOK_MODE=advisory to nudge-only.
# Thin entry: skill-specific config only; the shared flow (pre-filter, strip,
# marker check, rewind re-validation, advisory/strict delivery) lives in
# lib/intercept-gh-pr-common.sh. Fail CLOSED on missing python3 in strict mode;
# fail OPEN on other ambiguity, including a missing lib.

# shellcheck disable=SC2034  # consumed by lib/intercept-gh-pr-common.sh
INTERCEPT_SKILL_NAME="create-tickets"
INTERCEPT_GH_PR_VERB='issue-create'
INTERCEPT_SYSTEM_MESSAGE="lattice: bare gh issue create blocked — /create-tickets is the required path (strict)"
INTERCEPT_ADVICE='⚠️ Direct gh issue create detected. The create-tickets skill is the required path, not an optional one.

Use: Skill(skill: "lattice:create-tickets")
  or: /create-tickets

The create-tickets skill ensures proper ticket creation by:
- Running POST_SPLIT_CHECK on Spec acceptance (no orphan A* / invented scope)
- Batch grouping with independence gates (parallel vs serial)
- Writing durable binders with status FSM and cover partition
- Ship-plan declaration before EXECUTE'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HOOK_DIR}/lib/intercept-gh-pr-common.sh" 2>/dev/null || exit 0
intercept_gh_pr_main
