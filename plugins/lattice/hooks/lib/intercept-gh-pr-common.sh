#!/usr/bin/env bash
# Shared PreToolUse flow for the gh-pr intercept hooks (create + merge).
#
# Entry scripts (intercept-gh-pr-create.sh / intercept-gh-pr-merge.sh) define:
#   INTERCEPT_SKILL_NAME     — skill/marker name to check (e.g. create-pr)
#   INTERCEPT_GH_PR_VERB     — create|merge, classified after normalization
#   INTERCEPT_ADVICE         — guidance text (the trailing "Hook mode: ..."
#                              line is appended here, once hook_mode is known)
#   INTERCEPT_SYSTEM_MESSAGE — one-line pointer shown to the USER in advisory
# then source this file and call intercept_gh_pr_main. hooks.json keeps
# pointing at the entry scripts; a missing lib fails OPEN there (exit 0).
#
# Delivery contract (verified 2026-07 against code.claude.com/docs/en/hooks
# for current Claude Code releases):
#   advisory -> exit 0 + JSON on stdout: hookSpecificOutput.additionalContext
#               is passed to Claude next to the tool call; systemMessage is a
#               best-effort warning/notification (docs don't pin its audience).
#               stderr on exit 0 is DISCARDED by Claude Code, so stdout JSON is
#               the only advisory path that reaches the model. Deliberately NO
#               permissionDecision is emitted — "allow" would skip the user's
#               permission prompt, which is not this hook's job, and "ask"
#               would force prompts on already-allowlisted commands.
#   strict   -> exit 2 + advice on stderr (fed to the model, blocks the call).
# Fail OPEN on ambiguity: every failure mode must resolve to exit 0.

_INTERCEPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERCEPT_STRIP_HELPER="${_INTERCEPT_LIB_DIR}/../../scripts/strip-quoted-and-heredocs.py"
INTERCEPT_GH_PR_HELPER="${_INTERCEPT_LIB_DIR}/../../scripts/detect-gh-pr-command.py"
INTERCEPT_SKILL_ACTIVE_HELPER="${_INTERCEPT_LIB_DIR}/../../scripts/skill-active-in-transcript.py"
INTERCEPT_AS_ROOT_LIB="${_INTERCEPT_LIB_DIR}/../../scripts/activated-skills-root.sh"

intercept_gh_pr_main() {
    local hook_data hook_mode tool_name command cleaned_command
    local session_id agent_id marker_dir agent_marker_dir session_dir
    local transcript_path marker_hit rc advice

    hook_data=$(cat)

    hook_mode=$(printf '%s' "${LATTICE_HOOK_MODE:-advisory}" | tr '[:upper:]' '[:lower:]')
    case "$hook_mode" in advisory|strict) ;; *) hook_mode="advisory" ;; esac

    # Cheap pre-filter (advisory mode only): if "gh" appears nowhere in the
    # raw hook JSON, bail before spawning jq/python3. JSON \u escapes can
    # encode "gh" without the literal bytes (jq would decode them), so a
    # crafted payload CAN slip past this — skipping only an advisory nudge.
    # Strict mode never takes the shortcut, so its guard is unaffected.
    if [[ "$hook_mode" != strict && "$hook_data" != *gh* ]]; then
        exit 0
    fi

    # One jq pass for the scalar metadata. Regex-scraping the raw JSON for
    # session_id/agent_id/transcript_path would silently depend on Claude Code
    # serializing those keys before tool_input; jq is already paid for here.
    # Read line-by-line rather than splitting on a delimiter: tab and space are
    # IFS whitespace, so `read -d` would collapse the empty agent_id field and
    # shift transcript_path into it. gsub keeps one value on one line.
    local meta
    if ! meta=$(printf '%s' "$hook_data" | jq -r '
        (.tool_name // ""), (.session_id // ""), (.agent_id // ""),
        (.transcript_path // "") | gsub("\n"; " ")' 2>/dev/null); then
        exit 0
    fi
    {
        IFS= read -r tool_name
        IFS= read -r session_id
        IFS= read -r agent_id
        IFS= read -r transcript_path
    } <<<"$meta"
    # The command is queried separately: it legitimately contains newlines.
    command=$(printf '%s' "$hook_data" | jq -r '.tool_input.command // empty' 2>/dev/null)

    if [[ "$tool_name" != "Bash" ]]; then
        exit 0
    fi

    # Strip helper unavailable/failed -> fail OPEN (contract). Matching the raw
    # command instead would false-block quoted mentions in strict mode.
    if ! cleaned_command=$(printf '%s' "$command" | python3 "$INTERCEPT_STRIP_HELPER" 2>/dev/null); then
        exit 0
    fi

    # Pragmatic direct-gh classifier: covers documented gh/pr inherited flag
    # placement without pretending to be an exhaustive shell security sandbox.
    # Missing/broken classifier follows the hook's fail-open contract.
    if [[ ! "${INTERCEPT_GH_PR_VERB:-}" =~ ^(create|merge)$ ]] || \
       ! printf '%s' "$cleaned_command" | python3 "$INTERCEPT_GH_PR_HELPER" "$INTERCEPT_GH_PR_VERB" 2>/dev/null; then
        exit 0
    fi

    if [[ -z "$session_id" || ! "$session_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        exit 0
    fi

    # shellcheck source=/dev/null
    source "$INTERCEPT_AS_ROOT_LIB" 2>/dev/null || exit 0
    AS_ROOT="$(activated_skills_root 2>/dev/null)" || exit 0
    [[ -n "$AS_ROOT" ]] || exit 0

    # Owned-root guarantee before the touch below: never write through a
    # symlinked or foreign root (C-11). prepare_root also closes the
    # check-then-mkdir race. If it fails, marker state is untrustworthy ->
    # fail OPEN without mutating anything.
    activated_skills_prepare_root "$AS_ROOT" 2>/dev/null || exit 0

    # Refresh this session's dir mtime on EVERY intercept check that finds it,
    # not only on marker hit — keeps an active session out of the
    # cross-session GC window even when no marker exists for this skill yet.
    session_dir="${AS_ROOT}/${session_id}"
    if [[ -d "$session_dir" && ! -L "$session_dir" ]]; then
        touch "$session_dir" 2>/dev/null || true
    fi

    marker_hit=0
    if [[ -n "$agent_id" && "$agent_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        agent_marker_dir="${session_dir}/${agent_id}"
        if [[ -f "${agent_marker_dir}/${INTERCEPT_SKILL_NAME}" || -f "${agent_marker_dir}/lattice:${INTERCEPT_SKILL_NAME}" ]]; then
            marker_hit=1
        fi
    else
        marker_dir="$session_dir"
        if [[ -f "${marker_dir}/${INTERCEPT_SKILL_NAME}" || -f "${marker_dir}/lattice:${INTERCEPT_SKILL_NAME}" ]]; then
            marker_hit=1
        fi
    fi

    if [[ "$marker_hit" -eq 1 ]]; then
        if [[ -n "$transcript_path" && -f "$transcript_path" ]] && command -v python3 >/dev/null 2>&1; then
            python3 "$INTERCEPT_SKILL_ACTIVE_HELPER" "$transcript_path" "$INTERCEPT_SKILL_NAME"
            rc=$?
            if [[ "$rc" -ne 1 ]]; then
                exit 0
            fi
        else
            exit 0
        fi
    fi

    advice="${INTERCEPT_ADVICE}
Hook mode: ${hook_mode} (set LATTICE_HOOK_MODE=strict to enforce the skill marker)."

    if [[ "$hook_mode" == "strict" ]]; then
        printf '%s\n' "$advice" >&2
        exit 2
    fi

    # Advisory delivery: hook JSON on stdout with exit 0. jq --arg escapes the
    # advice text; a broken jq degrades to a silent allow (fail open).
    jq -cn --arg ctx "$advice" --arg msg "$INTERCEPT_SYSTEM_MESSAGE" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx},systemMessage:$msg}' \
        2>/dev/null || true
    exit 0
}
