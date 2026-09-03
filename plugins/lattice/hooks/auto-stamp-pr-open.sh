#!/usr/bin/env bash
# PostToolUse (Bash): stamp the ticket binder `→ pr-open` right after a
# successful `gh pr create` (spc-337 A3 / ADR-012 §1, tkt-339).
#
# The create-pr skill's scripted step (skills/create-pr/scripts/after-pr-open.sh)
# is the portable writer of this edge. This hook is the Claude-side safety net:
# when the model ran `gh pr create` and the response carries the new PR's URL,
# the same idempotent stamp-pr-open.sh runs — so a skipped script step no
# longer leaves the binder at in-progress with an open PR (rev-20260902-015425Z
# F2: 15 of 22 PR-bearing ledgers had no pr-open entry). Both writers may run;
# stamp-pr-open is idempotent (second call changes nothing).
#
# Payload (Claude Code PostToolUse): {session_id, cwd, tool_name:"Bash",
#   tool_input:{command}, tool_response:{stdout,stderr,…} | "<string>"}.
# Both tool_response shapes are handled.
#
# Binding (review cycle 1, M1): stamp-pr-open.sh picks the binder from the
# CURRENT branch of the tree it runs in, so the hook must prove that tree IS
# the PR's head. It (1) resolves the tree the command actually ran in — a
# leading `cd <path> &&` prefix wins over the payload cwd; (2) determines the
# PR's head branch from `--head <branch>` in the command, else
# `gh pr view N --json headRefName`; (3) stamps ONLY when
# `git branch --show-current` in that tree equals the head branch. Anything
# else (mismatch, unknown head, main clone on dev, no binder) is reported
# honestly as "not stamped" — never as a stamp.
#
# Contract: ALWAYS exit 0. Every failure mode (missing jq/git, malformed JSON,
# non-gh command, no PR URL in the response, no Lattice home under the cwd's
# toplevel, stamp error) is fail-open — advisory on stderr, never a block.
# A successful or failed stamp is also reported to the model through
# hookSpecificOutput.additionalContext on stdout (stderr on exit 0 is not
# shown to the model).
set -uo pipefail

hook_data=$(cat)

advise() {  # <text>  — stdout JSON for the model (best effort), stderr for humans
  printf '%s\n' "$1" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ctx "$1" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}' \
      2>/dev/null || true
  fi
}

# Cheap pre-filter before spawning jq: no "gh" or no "/pull/" anywhere in the
# raw JSON → nothing to do.
if [[ "$hook_data" != *gh* || "$hook_data" != */pull/* ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "lattice: auto-stamp-pr-open inert — jq/git not found on PATH (fail-open; run create-pr's after-pr-open.sh)" >&2
  exit 0
fi

if ! tool_name=$(printf '%s' "$hook_data" | jq -r '.tool_name // empty' 2>/dev/null); then
  echo "lattice: auto-stamp-pr-open could not parse its input JSON — skipping (fail-open)" >&2
  exit 0
fi
[[ "$tool_name" == "Bash" ]] || exit 0

command_text=$(printf '%s' "$hook_data" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ "$command_text" == *"gh pr create"* ]] || exit 0

# tool_response: object (stdout/stderr/output fields) or a plain string.
response_text=$(printf '%s' "$hook_data" | jq -r '
  if (.tool_response|type) == "string" then .tool_response
  elif (.tool_response|type) == "object" then
    ((.tool_response.stdout // "") + "\n" + (.tool_response.stderr // "") + "\n" + (.tool_response.output // ""))
  else "" end' 2>/dev/null || true)
[[ -n "$response_text" ]] || exit 0

# First PR URL in the response wins: https://github.com/<owner>/<repo>/pull/<N>
pr_url=$(printf '%s' "$response_text" \
  | grep -oE 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[1-9][0-9]*' \
  | head -1 || true)
[[ -n "$pr_url" ]] || exit 0
pr_n="${pr_url##*/pull/}"
owner_repo="${pr_url#https://github.com/}"
owner_repo="${owner_repo%/pull/*}"

# --- Which tree did the command run in? -------------------------------------
# Payload cwd is the session cwd; a `cd <path> && gh pr create …` prefix moves
# the command elsewhere (e.g. a sibling worktree). Honour the LAST `cd` that
# precedes `gh pr create` in a simple &&/; chain; fail-open to the payload cwd.
hook_cwd=$(printf '%s' "$hook_data" | jq -r '.cwd // empty' 2>/dev/null || true)
[[ -n "$hook_cwd" && -d "$hook_cwd" ]] || hook_cwd="$PWD"
run_cwd="$hook_cwd"
cd_target=$(printf '%s' "$command_text" \
  | sed -E 's/gh pr create.*$//' \
  | grep -oE '(^|&&|;)[[:space:]]*cd[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:];&]+)' \
  | tail -1 \
  | sed -E 's/^(&&|;)?[[:space:]]*cd[[:space:]]+//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true)
if [[ -n "$cd_target" ]]; then
  # shellcheck disable=SC2088  # literal ~ prefix from the command text, expanded by hand
  case "$cd_target" in
    "~"|"~/"*) cd_target="${HOME}${cd_target#\~}" ;;
  esac
  if [[ "$cd_target" != /* ]]; then
    cd_target="$hook_cwd/$cd_target"
  fi
  if [[ -d "$cd_target" ]]; then
    run_cwd="$cd_target"
  fi
fi
if ! toplevel=$(git -C "$run_cwd" rev-parse --show-toplevel 2>/dev/null); then
  exit 0  # not a git work tree → nothing to stamp
fi
[[ -d "$toplevel/.lattice/tickets" ]] || exit 0  # not a Lattice repo → no-op

# --- Which branch is the PR's head? -----------------------------------------
# `--head <branch>` / `--head=<branch>` in the command wins (no network);
# else ask gh. Unknown head → cannot prove the binding → not stamped.
pr_head=$(printf '%s' "$command_text" \
  | grep -oE -- '(^|[[:space:]])(-H|--head)([[:space:]]+|=)("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:]"'"'"']+)' \
  | head -1 \
  | sed -E 's/^[[:space:]]*(-H|--head)([[:space:]]+|=)//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true)
if [[ -n "$pr_head" && "$pr_head" == *:* ]]; then
  pr_head="${pr_head#*:}"   # fork form owner:branch
fi
if [[ -z "$pr_head" ]] && command -v gh >/dev/null 2>&1; then
  pr_head=$(gh pr view "$pr_n" --repo "$owner_repo" --json headRefName -q .headRefName 2>/dev/null || true)
fi
if [[ -z "$pr_head" ]]; then
  advise "lattice: PostToolUse did NOT stamp pr-open for PR #$pr_n ($owner_repo) — could not determine the PR head branch (no --head in the command; gh pr view failed). Run create-pr's after-pr-open.sh --pr $pr_n --expected-oid <HEAD> from the PR's worktree."
  exit 0
fi

current_branch=$(git -C "$toplevel" branch --show-current 2>/dev/null || true)
if [[ -z "$current_branch" || "$current_branch" != "$pr_head" ]]; then
  advise "lattice: PostToolUse did NOT stamp pr-open for PR #$pr_n ($owner_repo) — current branch '${current_branch:-detached}' in $toplevel ≠ PR head '$pr_head'. Run create-pr's after-pr-open.sh --pr $pr_n --expected-oid <HEAD> from the PR's worktree."
  exit 0
fi

# _lattice-lib through the plugin root (hooks.json passes CLAUDE_PLUGIN_ROOT;
# fall back to this hook's own install tree).
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$plugin_root" ]]; then
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi
stamp="$plugin_root/skills/_lattice-lib/scripts/stamp-pr-open.sh"
if [[ ! -f "$stamp" ]]; then
  echo "lattice: auto-stamp-pr-open — stamp-pr-open.sh not found under $plugin_root (fail-open); run create-pr's after-pr-open.sh --pr $pr_n" >&2
  exit 0
fi

stamp_out=""
if stamp_out=$(cd "$toplevel" && bash "$stamp" --pr "$pr_n" --repo "$owner_repo" 2>&1); then
  last_line=$(printf '%s' "$stamp_out" | tail -1)
  # stamp-pr-open exits 0 on a no-binder skip too — report that honestly.
  if printf '%s' "$stamp_out" | grep -qE 'skip|no binder|not a tkt-'; then
    advise "lattice: PostToolUse did NOT stamp pr-open for PR #$pr_n ($owner_repo) on branch '$current_branch' — $last_line"
  else
    advise "lattice: PostToolUse stamped pr-open for PR #$pr_n ($owner_repo) on branch '$current_branch' — $last_line"
  fi
else
  advise "lattice: PostToolUse stamp-pr-open FAILED for PR #$pr_n ($owner_repo) — advisory only; re-run create-pr's after-pr-open.sh --pr $pr_n --expected-oid <HEAD>. Output: $(printf '%s' "$stamp_out" | tail -3 | tr '\n' ' ')"
fi
exit 0
