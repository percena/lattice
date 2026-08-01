#!/usr/bin/env bash
# Shared MAIN_ROOT + lattice-home resolution for lattice-lib callers.
# Source this file; do not execute it.
#
# Contract (spc-N naming; committed L0 layout):
#   Committed L0 (specs, reviews, ticket binders only — no global index/BOARD):
#     LATTICE_HOME if set, else <show-toplevel>/.lattice (current checkout /
#     feature worktree). Git worktrees do NOT share a working directory — writing
#     into MAIN_ROOT while EXECUTE is in a sibling worktree dirties the team-base
#     checkout and cannot be committed from the feature tip.
#
#   Claim markers only (gitignored .lattice/.ids/):
#     lattice_claim_home → MAIN_ROOT/.lattice so parallel worktrees share one
#     atomic id reservation tree.
#
#   MAIN_ROOT still used for worktree pool discovery and branch/worktree cleanup.
#
# Also exports:
#   LATTICE_REPO_ROOT  — current worktree/checkout top (show-toplevel)
#   LATTICE_MAIN_ROOT  — main checkout path when resolvable
#
# Keep lattice_main_root body in sync with ensure-workspace.sh and
# cleanup-workspace.sh (skills package independently).

lattice_main_root() {
  local repo_root git_common main_root
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  repo_root=$(git rev-parse --show-toplevel)
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    # git < 2.31: relative rev-parse output is relative to CWD
    git_common=$(git rev-parse --git-common-dir)
    [[ "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  if [[ "$git_common" == */.git ]]; then
    main_root="${git_common%/.git}"
  elif [[ "$git_common" == */.git/* ]]; then
    main_root="${git_common%%/.git/*}"
  else
    main_root="$repo_root"
  fi
  printf '%s' "$main_root"
}

# Committed L0 home (honours LATTICE_HOME). Empty only if no git and
# LATTICE_HOME unset — callers may fall back to ".lattice".
lattice_default_home() {
  if [[ -n "${LATTICE_HOME:-}" ]]; then
    printf '%s' "$LATTICE_HOME"
    return 0
  fi
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s' "$(git rev-parse --show-toplevel)/.lattice"
    return 0
  fi
  return 1
}

# Shared claim-marker home for next-artifact-id --claim (gitignored .ids/).
# Always prefer MAIN_ROOT so parallel worktrees (and ensure-workspace's
# advertised LATTICE_HOME=<worktree>/.lattice) cannot double-allocate spc/rev.
# LATTICE_HOME intentionally does NOT redirect claims — it only relocates
# committed L0. Explicit --home on next-artifact-id still keeps claims local
# (tests / single-home overrides). Falls back to lattice_default_home when
# MAIN_ROOT is unavailable (no git / bare clone edge).
#
# Submodule caveat: when run inside a git submodule, git-common-dir may resolve
# under the superproject's .git/modules/<name>; lattice_main_root then points at
# the superproject. Claims for submodule work should set an explicit
# next-artifact-id --home (or run from the superproject) so ids land in the
# intended repo's .lattice/.ids.
lattice_claim_home() {
  local main_root
  if main_root=$(lattice_main_root); then
    printf '%s' "$main_root/.lattice"
    return 0
  fi
  lattice_default_home
}

# Set LATTICE_REPO_ROOT / LATTICE_MAIN_ROOT for scripts that scan published docs.
lattice_export_roots() {
  LATTICE_REPO_ROOT=""
  LATTICE_MAIN_ROOT=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    LATTICE_REPO_ROOT=$(git rev-parse --show-toplevel)
    LATTICE_MAIN_ROOT=$(lattice_main_root || true)
  fi
  export LATTICE_REPO_ROOT LATTICE_MAIN_ROOT
}

# ---------------------------------------------------------------------------
# Profile (spc-N naming; strict default | light):
# Resolution order:
#   1. LATTICE_PROFILE env (strict|light)
#   2. .lattice/config.yaml key `profile:` (first match)
#   3. strict
# light does NOT relax bind law (still tkt-/spc-). It documents shippable
# --mode branch as allowed and softens alignment-check Acceptance HARD → WARN.
# ---------------------------------------------------------------------------
lattice_profile() {
  local raw home cfg
  if [[ -n "${LATTICE_PROFILE:-}" ]]; then
    raw=$(printf '%s' "$LATTICE_PROFILE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    case "$raw" in
      light|strict) printf '%s' "$raw"; return 0 ;;
      *)
        echo "Warning: LATTICE_PROFILE='$LATTICE_PROFILE' ignored (use strict|light); defaulting strict" >&2
        printf '%s' "strict"
        return 0
        ;;
    esac
  fi
  home=""
  if home=$(lattice_default_home 2>/dev/null); then
    :
  else
    home="${LATTICE_HOME:-}"
  fi
  if [[ -n "$home" && -f "$home/config.yaml" ]]; then
    cfg=$(grep -E '^[[:space:]]*profile:[[:space:]]*' "$home/config.yaml" 2>/dev/null | head -1 || true)
    if [[ -n "$cfg" ]]; then
      raw=$(printf '%s' "$cfg" | sed -E 's/^[[:space:]]*profile:[[:space:]]*//; s/[[:space:]]*[#].*$//')
      raw=$(printf '%s' "$raw" | tr -d " \"'" | tr '[:upper:]' '[:lower:]')
      case "$raw" in
        light|strict) printf '%s' "$raw"; return 0 ;;
      esac
    fi
  fi
  printf '%s' "strict"
}

lattice_profile_is_light() {
  [[ "$(lattice_profile)" == "light" ]]
}
