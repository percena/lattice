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
# Default is strict (governance hardening, spc-145 follow-up). Override to
# advisory for one shell: export LATTICE_HOOK_MODE=advisory
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

    hook_mode=$(printf '%s' "${LATTICE_HOOK_MODE:-strict}" | tr '[:upper:]' '[:lower:]')
    case "$hook_mode" in advisory|strict) ;; *) hook_mode="strict" ;; esac

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

    # python3 absent: the strip / classifier / skill-active checks below all
    # fail-open, so the gh-pr guardrail is inert. Emit a ONE-TIME stdout JSON
    # advisory (stderr is discarded on exit 0, so stdout is the only path that
    # reaches the model). Never block — fail-open even in strict mode
    # (spc-212 A3/D3: blocking user ops because a guardrail's own python is
    # missing is hostile). Gate on the command containing "gh" so the advisory
    # does not fire on unrelated Bash calls (strict mode skips the *gh*
    # pre-filter at line 47).
    if ! command -v python3 >/dev/null 2>&1 && [[ "$command" == *gh* ]]; then
        jq -cn --arg ctx "Lattice gh-pr guardrail is INERT: python3 is not installed, so the create-pr/finish-work/create-tickets skill-marker check is skipped (fail-open). Strict-mode protections are inactive until python3 is installed (see ensure-python3.sh)." \
            --arg msg "lattice: gh-pr guardrail degraded (python3 missing); protections inactive" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx},systemMessage:$msg}' \
            2>/dev/null || true
        exit 0
    fi

    # Strip helper unavailable/failed -> fail OPEN (contract). Matching the raw
    # command instead would false-block quoted mentions in strict mode.
    if ! cleaned_command=$(printf '%s' "$command" | python3 "$INTERCEPT_STRIP_HELPER" 2>/dev/null); then
        exit 0
    fi

    # Pragmatic direct-gh classifier: covers documented gh/pr inherited flag
    # placement without pretending to be an exhaustive shell security sandbox.
    # Nested-shell payloads (bash -c '…', eval "…") are invisible by design —
    # the strip helper removes quoted payloads upstream; see the detector
    # docstring's "Accepted limitation". Strict mode guards direct commands.
    # Missing/broken classifier follows the hook's fail-open contract.
    if [[ ! "${INTERCEPT_GH_PR_VERB:-}" =~ ^(create|merge|issue-create)$ ]] || \
       ! printf '%s' "$cleaned_command" | python3 "$INTERCEPT_GH_PR_HELPER" "$INTERCEPT_GH_PR_VERB" 2>/dev/null; then
        exit 0
    fi

    # Batch-work merge gate (spc-186 A1, ADR-007 five-piece contract): a bare
    # `gh pr merge` while the .batch-work-active marker is present at the repo
    # MAIN clone .lattice/ is blocked fail-closed. Runs only for the merge verb;
    # create is unaffected. Fails CLOSED (tkt-239) when LATTICE_BATCH_GATE_HOME
    # is unset and the lattice home cannot be resolved — a misresolvable home
    # makes an active marker invisible, so the gate must not silently allow.
    if [[ "${INTERCEPT_GH_PR_VERB:-}" == "merge" ]]; then
        # shellcheck source=/dev/null
        source "${_INTERCEPT_LIB_DIR}/batch-merge-gate.sh" 2>/dev/null || exit 0
        local bg_rc=0
        batch_gate_allows_merge 2>/dev/null || bg_rc=$?
        if [ "$bg_rc" -ne 0 ]; then
            if [[ "$hook_mode" == "strict" ]]; then
                if [[ "${BATCH_GATE_BLOCK_REASON:-}" == "unresolvable-home" ]]; then
                    cat >&2 <<'EOF'
lattice: batch-work merge gate cannot resolve the lattice home.

  LATTICE_BATCH_GATE_HOME is unset and the repo MAIN .lattice/ could not be
  resolved (non-standard layout / submodule / no .lattice). The gate FAILS
  CLOSED (tkt-239): an active .batch-work-active marker under a misresolvable
  home would otherwise be invisible and silently allow a merge.

  To proceed, either:
    1. Set LATTICE_BATCH_GATE_HOME=<MAIN>/.lattice and retry, OR
    2. Run: batch-merge-gate.sh --remove --reason "user-authorized: <why>"
       (records the escape in the binder ## Decision journal), OR
    3. Use /finish-work which resolves the gate through the scripted path.

  Failing closed is intentional — set the env var or clear the marker.
EOF
                else
                    batch_gate_advice_text >&2
                fi
                exit 2
            fi
            # Advisory: JSON on stdout (exit 0) so the model sees the context.
            local batch_advice
            batch_advice=$(batch_gate_advice_text)
            jq -cn --arg ctx "$batch_advice" \
                --arg msg "lattice: batch-work merge gate blocked gh pr merge (marker present)" \
                '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx},systemMessage:$msg}' \
                2>/dev/null || true
            exit 0
        fi
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

    # Build skill-name list: primary + optional alternate. The issue-create
    # hook sets INTERCEPT_SKILL_NAME_ALT=create-spec because create-spec also
    # legitimately calls gh issue create (references/issue-and-write.md).
    local skill_names=("$INTERCEPT_SKILL_NAME")
    [[ -n "${INTERCEPT_SKILL_NAME_ALT:-}" ]] && skill_names+=("$INTERCEPT_SKILL_NAME_ALT")
    local hit_skill=""

    marker_hit=0
    if [[ -n "$agent_id" && "$agent_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        agent_marker_dir="${session_dir}/${agent_id}"
        for skill_name in "${skill_names[@]}"; do
            if [[ -f "${agent_marker_dir}/${skill_name}" || -f "${agent_marker_dir}/lattice:${skill_name}" ]]; then
                marker_hit=1
                hit_skill="$skill_name"
                break
            fi
        done
    else
        marker_dir="$session_dir"
        for skill_name in "${skill_names[@]}"; do
            if [[ -f "${marker_dir}/${skill_name}" || -f "${marker_dir}/lattice:${skill_name}" ]]; then
                marker_hit=1
                hit_skill="$skill_name"
                break
            fi
        done
    fi

    if [[ "$marker_hit" -eq 1 ]]; then
        if [[ -n "$transcript_path" && -f "$transcript_path" ]] && command -v python3 >/dev/null 2>&1; then
            python3 "$INTERCEPT_SKILL_ACTIVE_HELPER" "$transcript_path" "$hit_skill"
            rc=$?
            if [[ "$rc" -ne 1 ]]; then
                exit 0
            fi
        else
            exit 0
        fi
    fi

    if [[ "$hook_mode" == "strict" ]]; then
        advice="${INTERCEPT_ADVICE}
Hook mode: strict (default; set LATTICE_HOOK_MODE=advisory to nudge-only)."
    else
        advice="${INTERCEPT_ADVICE}
Hook mode: advisory (set LATTICE_HOOK_MODE=strict to enforce the skill marker)."
    fi

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
