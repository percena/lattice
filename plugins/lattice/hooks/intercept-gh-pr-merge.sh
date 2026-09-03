#!/usr/bin/env bash
# PreToolUse: block bare `gh pr merge` unless finish-work is active.
# Default mode is strict (blocks). Set LATTICE_HOOK_MODE=advisory to nudge-only.
# Thin entry: skill-specific config only; the shared flow (pre-filter, strip,
# marker check, rewind re-validation, advisory/strict delivery) lives in
# lib/intercept-gh-pr-common.sh. Fail OPEN on ambiguity, including a missing lib.
# Does NOT edit issue/PR/binder bodies.

# shellcheck disable=SC2034  # consumed by lib/intercept-gh-pr-common.sh
INTERCEPT_SKILL_NAME="finish-work"
INTERCEPT_GH_PR_VERB='merge'
INTERCEPT_SYSTEM_MESSAGE="lattice: bare gh pr merge blocked — /finish-work is the required path (strict)"
INTERCEPT_ADVICE='⚠️ Direct gh pr merge detected. The finish-work skill is the required path, not an optional one.

Use: Skill(skill: "lattice:finish-work")
  or: /finish-work pr <N>
  or: /finish-work tkt <N>

finish-work ensures a safe land by:
- Updating the PR branch onto its base when behind (gh pr update-branch / optional rebase)
- Running alignment-check + artifact alignment (§2.5) — HARD if Fixes/Closes issues still have open Acceptance boxes (check off issue + binder; hooks do not edit bodies)
- Squash-merge, branch/worktree cleanup, and ticket binders

(Hook is Claude-only; Codex uses the portable skill without this reminder.)'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HOOK_DIR}/lib/intercept-gh-pr-common.sh" 2>/dev/null || exit 0
intercept_gh_pr_main
