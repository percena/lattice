#!/usr/bin/env bash
# UserPromptSubmit: record skill activation for lattice slash loads that may
# skip the Skill tool (create-pr, finish-work). Writes bare + lattice: markers.

hook_data=$(cat)

if [[ "$hook_data" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    session_id="${BASH_REMATCH[1]}"
else
    exit 0
fi

if [[ ! "$session_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    exit 0
fi

# No prompt field -> nothing to classify. Never fall back to scanning the
# whole hook JSON: an unanchored match there diverges from the anchored
# transcript scanner (skill-active-in-transcript.py) and lets arbitrary JSON
# context (paths, quoted text) mint an activation marker.
prompt=""
if [[ "$hook_data" =~ \"prompt\"[[:space:]]*:[[:space:]]*\"((\\.|[^\"\\])*)\" ]]; then
    prompt="${BASH_REMATCH[1]}"
fi
if [[ -z "$prompt" ]]; then
    exit 0
fi

prompt=$(printf '%b' "$prompt" 2>/dev/null || printf '%s' "$prompt")

# Match only bare or exact lattice: forms for create-pr / finish-work
# (hard cut — no foreign plugin namespaces).
# Prompt path and <command-name> path share the same allowlist below.
skill_raw=""
if [[ "$prompt" =~ ^[[:space:]]*(/(create-pr|finish-work|lattice:create-pr|lattice:finish-work))([[:space:]]|$) ]]; then
    # Anchored at the START of the prompt, exactly like the transcript scanner
    # (_SLASH_RE in skill-active-in-transcript.py). A slash command is only a
    # slash command in first position; matching mid-prompt let prose such as
    # "maybe run /create-pr later" mint an authorizing marker.
    skill_raw="${BASH_REMATCH[1]}"
elif [[ "$prompt" =~ ^[[:space:]]*\<command-(name|message)\> ]] \
  && [[ "$prompt" =~ \<command-name\>/?(create-pr|finish-work|lattice:create-pr|lattice:finish-work)\</command-name\> ]]; then
    # Only trust <command-name> when the prompt genuinely IS a synthesized
    # command block (opens with the tag) — same anchor rule as the transcript
    # scanner; prose merely quoting the tag must not count.
    skill_raw="/${BASH_REMATCH[1]}"
fi

if [[ -z "$skill_raw" ]]; then
    exit 0
fi

skill_raw="${skill_raw#/}"

case "$skill_raw" in
  create-pr|finish-work|lattice:create-pr|lattice:finish-work) ;;
  *) exit 0 ;;
esac

skill_component="${skill_raw##*:}"

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_HOOK_DIR}/../scripts/activated-skills-root.sh" 2>/dev/null || exit 0
AS_ROOT="$(activated_skills_root 2>/dev/null)" || exit 0
[[ -n "$AS_ROOT" ]] || exit 0
activated_skills_prepare_root "$AS_ROOT" 2>/dev/null || exit 0

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
# Always record bare + lattice: authorizing markers for valid Lattice forms only.
touch "${marker_dir}/${skill_component}"
touch "${marker_dir}/lattice:${skill_component}"

touch "${AS_ROOT}/${session_id}"
# TTL contract shared with track-skill-activation.sh (default 72h).
ttl_hours=$(printf '%s' "${LATTICE_SKILL_MARKER_TTL_HOURS:-72}" | tr -cd '0-9')
[[ -n "$ttl_hours" && "$ttl_hours" -gt 0 ]] || ttl_hours=72
# Clamp absurd values — see track-skill-activation.sh: without
# this, a huge TTL overflows $((ttl_hours * 60)) to a negative `-mmin`, which
# is MATCH-ALL on BSD find (macOS) and would wipe every sibling session.
(( ttl_hours > 100000 )) && ttl_hours=100000
if activated_skills_root_is_owned "$AS_ROOT"; then
    find "$AS_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name "$session_id" -mmin +"$((ttl_hours * 60))" -exec rm -rf -- {} + 2>/dev/null &
fi

exit 0
