#!/usr/bin/env bash
# Synchronous PreToolUse:Skill hook that records skill activations.
#
# Writes a marker file per session+skill so other hooks can deterministically
# check whether a given skill has been loaded in this session.
#
# Marker location (see ../scripts/activated-skills-root.sh):
#   {AS_ROOT}/{session_id}/{skill_name}
#   {AS_ROOT}/{session_id}/{agent_id}/{skill_name}  (inside subagents)
#
# Markers are cleared on context compaction (by clear-skill-markers-on-compact.sh)
# so the agent must re-invoke skills after compaction.
#
# This replaces the old approach of grepping the transcript for skill names,
# which caused false positives when file contents happened to mention a skill.

hook_data=$(cat)

# Pure bash JSON extraction — avoids jq overhead on every Skill call
# Regex handles both minified ("key":"val") and pretty-printed ("key": "val") JSON
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

if [[ "$hook_data" =~ \"skill\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    skill_name="${BASH_REMATCH[1]}"
else
    exit 0
fi

# Marker name becomes a filename — restrict charset like the slash-command
# variant does (allows plugin-qualified lattice:create-pr form).
if [[ ! "$skill_name" =~ ^[A-Za-z0-9_:-]+$ ]]; then
    exit 0
fi

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
# Fail OPEN if the shared resolver is missing (partial install): skip marker
# bookkeeping entirely — the intercept guards likewise allow in that state.
source "${_HOOK_DIR}/../scripts/activated-skills-root.sh" 2>/dev/null || exit 0
AS_ROOT="$(activated_skills_root 2>/dev/null)" || exit 0
[[ -n "$AS_ROOT" ]] || exit 0
activated_skills_prepare_root "$AS_ROOT" 2>/dev/null || exit 0

# Scope markers to agent_id when running inside a subagent, so that a skill
# activated in one agent doesn't unlock guarded commands for other agents.
# Invalid/empty agent_id: fall back to session-scoped markers (same as
# intercept-gh-pr-create) so activation is never silently dropped.
if [[ "$hook_data" =~ \"agent_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    agent_id="${BASH_REMATCH[1]}"
    if [[ -n "$agent_id" && "$agent_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        marker_dir="${AS_ROOT}/${session_id}/${agent_id}"
    else
        marker_dir="${AS_ROOT}/${session_id}"
    fi
else
    marker_dir="${AS_ROOT}/${session_id}"
fi
mkdir -p "$marker_dir"
touch "${marker_dir}/${skill_name}"

# Keep this session's top dir fresh, then GC dirs untouched for longer than
# the TTL (LATTICE_SKILL_MARKER_TTL_HOURS, default 72h; non-numeric/zero
# falls back to the default). Without the touch, a session idle past the TTL
# would have its own markers GC'd mid-session, silently re-engaging the
# gh pr create guard on next use.
touch "${AS_ROOT}/${session_id}"
ttl_hours=$(printf '%s' "${LATTICE_SKILL_MARKER_TTL_HOURS:-72}" | tr -cd '0-9')
[[ -n "$ttl_hours" && "$ttl_hours" -gt 0 ]] || ttl_hours=72
# Clamp absurd values: bash `[[` accepts a 20+ digit integer as positive, but
# $((ttl_hours * 60)) would then overflow 64-bit signed arithmetic to a
# negative, emitting `find ... -mmin +<negative>`. On BSD find (macOS) that is
# MATCH-ALL — GC wipes every sibling session dir, including fresh ones (a real
# data-loss path, not fail-safe); other finds reject the negative. 100000h
# ≈ 11.4 years is a sane upper bound.
(( ttl_hours > 100000 )) && ttl_hours=100000
if activated_skills_root_is_owned "$AS_ROOT"; then
    find "$AS_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name "$session_id" -mmin +"$((ttl_hours * 60))" -exec rm -rf -- {} + 2>/dev/null &
fi

exit 0
