#!/usr/bin/env bash
# PreCompact hook that clears skill activation markers.
#
# After context compaction, the agent loses awareness of previously loaded
# skills. Without clearing markers, the intercept-gh-pr-create hook would
# still find a stale marker and allow gh pr create through — even though
# the agent no longer has the create-pr skill instructions in context.

hook_data=$(cat)

if [[ "$hook_data" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    session_id="${BASH_REMATCH[1]}"
else
    exit 0
fi

# session_id becomes a path component (and a find -name pattern) — enforce a
# safe charset before any filesystem use (Claude session ids are UUIDs).
if [[ ! "$session_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    exit 0
fi

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
# Fail OPEN if the shared resolver is missing (partial install): skip marker
# bookkeeping entirely — the intercept guards likewise allow in that state.
source "${_HOOK_DIR}/../scripts/activated-skills-root.sh" 2>/dev/null || exit 0
AS_ROOT="$(activated_skills_root 2>/dev/null)" || exit 0
[[ -n "$AS_ROOT" ]] || exit 0

# Recursive delete only under a root that passes the same symlink/ownership
# checks the writers enforce (activated_skills_prepare_root) — never rm -rf
# through a symlinked or foreign-owned root/dir. Failure -> skip clearing;
# the intercepts re-validate markers against the transcript anyway.
[[ -d "$AS_ROOT" && ! -L "$AS_ROOT" && -O "$AS_ROOT" ]] || exit 0

# Clear both session-scoped and agent-scoped markers
marker_dir="${AS_ROOT}/${session_id}"
if [[ -d "$marker_dir" && ! -L "$marker_dir" && -O "$marker_dir" ]]; then
    rm -rf "$marker_dir"
fi

exit 0
