#!/usr/bin/env bash
# PreToolUse (Bash): block raw git branch-create / switch in the main clone.
#
# Forces agents through ensure-workspace.sh (the blessed entry) so worktree
# discipline is machine-enforced under strict profile. The existing HARD gate
# (assert-shippable-cwd.sh) only blocks team-base writes; it deliberately
# passes a non-base branch on the main clone — the recorded drift path. This
# hook closes that gap at the moment of branch creation/switch.
#
# Why this matches only RAW git ops, not ensure-workspace:
#   The hook fires on each Bash TOOL call. ensure-workspace is invoked as
#   `bash …/ensure-workspace.sh …`; its internal `git branch` / `git worktree
#   add` / `git checkout -b` are subprocess calls inside that script, NOT a
#   separate Bash tool call, so they never reach this hook. A bound-name
#   create like `git checkout -b tkt-8-foo` typed directly by the agent IS
#   matched and blocked — gating on LOCATION, not name (the recorded drift
#   used a bound name).
#
# Allow:
#   - inside a linked worktree ($PWD toplevel != MAIN_ROOT)
#   - switching TO a base branch (main / dev / master / default)
#   - `git checkout <name>` where <name> is not an existing local branch
#     (file restore) — fail open
# Block:
#   - op=create  in the main clone (any name)
#   - op=switch  to a non-base existing local branch in the main clone
#
# Delivery contract (Claude Code PreToolUse):
#   block  -> exit 2 + stderr advice (fed to the model, blocks the call)
#   allow -> exit 0 (no stdout needed)
# Fail OPEN on ambiguity: missing jq/python3, parse failure, non-Bash tool,
# non-git command, not-in-a-work-tree, submodule — all resolve to exit 0.
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR="${HOOK_DIR}/../scripts/detect-git-branch-op.py"
STRIP="${HOOK_DIR}/../scripts/strip-quoted-and-heredocs.py"

hook_data=$(cat)

# Cheap pre-filter: "git" must appear somewhere in the payload.
if [[ "$hook_data" != *git* ]]; then
  exit 0
fi

# tkt-239: a missing required dependency makes this gate silently inert. Keep
# fail-open (don't break missing-dep envs) but emit a once-per-session stderr
# advisory so the gap is visible. Sentinel is keyed by session_id (extracted
# without jq, since jq may be the missing dep).
_lattice_dep_advisory() {
  local missing="$1" sid sentinel
  sid=$(printf '%s' "$hook_data" 2>/dev/null \
    | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
    | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null \
    || true)
  sentinel="${TMPDIR:-/tmp}/lattice-hook-dep-missing-${sid:-default}"
  if [[ -e "$sentinel" ]]; then return 0; fi
  { : > "$sentinel"; } 2>/dev/null || true
  cat >&2 <<EOF
lattice: enforcement hook inert — required dependency (${missing}) not found on PATH.
  The strict-profile L1 git-branch gate cannot enforce; raw git branch-create /
  switch ops in the main clone will be ALLOWED. Install the missing dependency
  to restore protection. (advisory only, not a block; printed once per session)
EOF
}

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  _missing=""
  command -v jq >/dev/null 2>&1 || _missing="jq"
  command -v python3 >/dev/null 2>&1 || _missing="${_missing:+$_missing }python3"
  _lattice_dep_advisory "$_missing"
  exit 0
fi

tool_name=$(printf '%s' "$hook_data" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$hook_data" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -n "$command" ]] || exit 0

# Cheap pre-filter 2: command must mention git.
case "$command" in
  *git*) ;;
  *) exit 0 ;;
esac

# Working directory: prefer the hook JSON's .cwd (tracks agent's persistent
# shell CWD, confirmed by Claude Code hooks docs); fall back to $PWD.
hook_cwd=$(printf '%s' "$hook_data" | jq -r '.cwd // empty' 2>/dev/null)
[[ -n "$hook_cwd" ]] || hook_cwd="$PWD"

if ! cleaned=$(printf '%s' "$command" | python3 "$STRIP" 2>/dev/null); then
  exit 0
fi

if [[ ! -f "$DETECTOR" ]]; then exit 0; fi
det=$(printf '%s' "$cleaned" | python3 "$DETECTOR" 2>/dev/null) || exit 0
[[ -n "$det" ]] || exit 0

op=$(printf '%s' "$det" | jq -r '.op // "none"' 2>/dev/null)
target=$(printf '%s' "$det" | jq -r '.target // empty' 2>/dev/null)
cwd_override=$(printf '%s' "$det" | jq -r '.cwd_override // empty' 2>/dev/null)
[[ "$op" != "none" ]] || exit 0

# Effective directory for the location check: a `git -C <path>` override
# names where the op actually lands; otherwise the agent's cwd.
check_dir="$hook_cwd"
if [[ -n "$cwd_override" ]]; then
  check_dir="$cwd_override"
fi

if ! git_top=$(git -C "$check_dir" rev-parse --show-toplevel 2>/dev/null); then exit 0; fi
git_common=$(git -C "$check_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[[ -n "$git_common" && "$git_common" != /* ]] && git_common="$check_dir/$git_common"
if [[ -z "$git_common" ]]; then exit 0; fi

# Submodule checkout: fail open (ensure-workspace refuses these too).
if [[ "$git_common" == */.git/modules/* ]]; then
  exit 0
fi

# Derive MAIN_ROOT (the main clone root) from the shared common dir.
case "$git_common" in
  */.git)  main_root="${git_common%/.git}" ;;
  */.git/*) main_root="${git_common%%/.git/*}" ;;
  *)       main_root="$git_top" ;;
esac

# Inside a linked worktree? toplevel != main_root -> allow (already isolated).
if [[ "$(cd "$git_top" 2>/dev/null && pwd -P)" != "$(cd "$main_root" 2>/dev/null && pwd -P)" ]]; then
  exit 0
fi

# On the main clone. For switch ops, allow base-branch switches and file restores.
if [[ "$op" == "switch" ]]; then
  default_base=$(git -C "$check_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
  # Also honor a configured base_branch (.lattice/config.yaml) so the L1 gate's
  # notion of "base" matches assert-shippable-cwd.sh (spc-145 review F1).
  cfg_base=""
  for cfg in "$git_top/.lattice/config.yaml" "$main_root/.lattice/config.yaml"; do
    [[ -f "$cfg" ]] || continue
    cfg_line=$(grep -E '^[[:space:]]*base_branch:[[:space:]]*' "$cfg" 2>/dev/null | head -1 || true)
    if [[ -n "$cfg_line" ]]; then
      cfg_base=$(printf '%s' "$cfg_line" | sed -E 's/^[[:space:]]*base_branch:[[:space:]]*//; s/[[:space:]]*[#].*$//; s/["'"'"']//g' | tr -d '[:space:]')
      break
    fi
  done
  for b in main master dev "$default_base" "$cfg_base"; do
    if [[ -n "$b" && "$target" == "$b" ]]; then exit 0; fi
  done
  # Not an existing local branch -> likely a file/path restore -> fail open.
  if [[ -n "$target" ]] && ! git -C "$check_dir" show-ref --verify --quiet "refs/heads/$target" 2>/dev/null; then
    exit 0
  fi
fi

# Block.
cat >&2 <<EOF
lattice: raw git branch op blocked in the main clone.

  op:     $op ${target:-(none)}
  cwd:    $check_dir (main clone; main_root=$main_root)

Under strict profile, do not create or switch to a feature branch in the main
clone — the main checkout stays parked on the integration branch. Use the
blessed entry instead:

  /start-work                                          (ticket + worktree)
  bash …/ensure-workspace.sh --mode worktree --bind tkt --id <N> --slug <slug>

For a non-standard flow (plain branch or base-direct commit), ASK THE USER
first, then route through the audited escape so the reason is recorded:

  ensure-workspace.sh --mode branch --branch <name> --allow-unbound --reason "user-authorized: <why>"
  assert-shippable-cwd.sh --allow-base-write --reason "user-authorized: <why>"

Switching to a base branch (main/dev/master) is always allowed. Inside a linked
worktree, raw git ops are always allowed.
EOF
exit 2
