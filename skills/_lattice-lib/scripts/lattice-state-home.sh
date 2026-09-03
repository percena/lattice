#!/usr/bin/env bash
# lattice-state-home.sh — resolve Lattice's out-of-repo runtime state directory.
#
# ADR-011 / spc-282: pure per-clone runtime state (batch gate markers,
# coordinator spine, transition-ledger .lock sidecars) lives OUTSIDE the repo
# tree so it never leaks as untracked dirt in a fresh customer repo. The dir is
# keyed by a repo fingerprint so all sibling worktrees of one MAIN clone resolve
# to ONE directory (single-gate-point preserved, spc-186 A1).
#
# Resolution priority:
#   1. LATTICE_STATE_HOME  — explicit override (the dir that CONTAINS the markers;
#      tests / manual pin). For backward compat LATTICE_BATCH_GATE_HOME is also
#      honoured as a marker-parent override.
#   2. ${XDG_STATE_HOME:-$HOME/.local/state}/lattice/<fingerprint>
#      where fingerprint = sha1("$(git rev-parse --git-common-dir)" abs path)[:12]
#
# State (not cache) is the XDG category: state must persist across sessions
# (replaces the abandoned BATCH_WORK=1 env-var gate) but is not project data;
# cache may be auto-cleaned by OS utilities (fail-open risk for a fail-closed
# gate — ADR-011 §Risks).
#
# Prints the resolved dir to stdout (mkdir -p'd); exits 0 on success, 1 if the
# git common dir cannot be resolved and no override is set.
set -euo pipefail

lattice_state_home() {
  local override="${LATTICE_STATE_HOME:-${LATTICE_BATCH_GATE_HOME:-}}"
  if [[ -n "$override" ]]; then
    printf '%s' "$override"
    return 0
  fi
  local git_common
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    # git < 2.31 fallback: relative rev-parse output is relative to CWD.
    git_common=$(git rev-parse --git-common-dir 2>/dev/null || true)
    [[ -n "$git_common" && "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  [[ -n "$git_common" ]] || return 1
  local fingerprint
  # fingerprint = sha1(abspath)[:12]; printf '%s' to avoid trailing newline
  fingerprint=$(printf '%s' "$git_common" | shasum | cut -c1-12 2>/dev/null || true)
  # BSD shasum fallback to sha1sum (Linux coreutils)
  [[ -n "$fingerprint" ]] || fingerprint=$(printf '%s' "$git_common" | sha1sum 2>/dev/null | cut -c1-12 || true)
  [[ -n "$fingerprint" ]] || return 1
  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/lattice"
  local home="$state_root/$fingerprint"
  printf '%s' "$home"
}

home=$(lattice_state_home) || { echo "lattice-state-home: could not resolve state dir (no LATTICE_STATE_HOME override and git common dir unresolvable)" >&2; exit 1; }
mkdir -p "$home"
printf '%s\n' "$home"
