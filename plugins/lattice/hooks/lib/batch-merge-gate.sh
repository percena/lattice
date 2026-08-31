#!/usr/bin/env bash
# shellcheck disable=SC2034  # BATCH_GATE_BLOCK_REASON is set here and consumed by
#                            # the intercept-gh-pr-common.sh hook that sources this lib.
# Batch-work merge gate — spc-186 A1, ADR-007 five-piece contract.
#
# Blocks a bare `gh pr merge` while the batch-work marker is present, fail-closed
# in strict mode. Per ADR-011 / spc-282, the marker now lives OUT OF THE REPO
# TREE at $XDG_STATE_HOME/lattice/<repo-fingerprint>/.batch-work-active (macOS
# fallback $HOME/.local/state/lattice/<fp>/) — keyed by sha1(git common-dir
# abspath)[:12] so all sibling worktrees of one MAIN clone resolve ONE marker
# (single gate point preserved, spc-186 A1; per-worktree copies retired). This
# stops the marker leaking as untracked dirt in fresh customer repos with no
# pre-existing Lattice gitignore.
#
# Five pieces (ADR-007 §4 — a hard rule without all five is not done):
#   check  — batch_gate_allows_merge: is the marker present at the state dir?
#   message — batch_gate_advice_text: the rule, why it exists, the legal escape
#   escape — operator removes the marker, OR sets an authorized-merge flag file
#            (.batch-merge-authorized) carrying a structured reason; trace in
#            binder ## Decision journal; counted for digest metric
#   trace  — finish-work records the removal/authorization in the binder
#            ## Decision journal (rule id, reason, authorizer, timestamp);
#            chat is not a trace (ADR-007 §6)
#   metric — escape counts surface in the morning digest (ADR-007 §8); a high
#            rate means the boundary is misplaced
#
# Sourced by lib/intercept-gh-pr-common.sh for the merge verb ONLY. The create
# verb is unaffected. Fails OPEN on ambiguity (missing root, broken git) per the
# hook contract — a missing root never deadlocks a legitimate merge.
# (tkt-239: the home-unresolvable case now fails CLOSED; see batch_gate_allows_merge.)

BATCH_GATE_MARKER=".batch-work-active"
BATCH_GATE_AUTH=".batch-merge-authorized"

# Resolve the Lattice runtime state home (OUT OF REPO per ADR-011 / spc-282).
# The marker lives here, not at <MAIN>/.lattice/, so it never leaks as untracked
# dirt in a fresh customer repo. Priority:
#   1. LATTICE_BATCH_GATE_HOME — explicit override (tests / manual pin); the dir
#      that CONTAINS the marker (backward compat with pre-ADR-011 tests).
#   2. LATTICE_STATE_HOME — explicit override (the marker-parent dir).
#   3. _lattice-lib/scripts/lattice-state-home.sh — canonical resolver:
#        ${XDG_STATE_HOME:-$HOME/.local/state}/lattice/<sha1(common-dir)[:12]>
#   4. INLINE fallback — same algorithm as lattice-state-home.sh, used when the
#      helper script cannot be located (e.g. a consumer repo where _lattice-lib
#      is not at a repo-relative path at hook fire time). Kept in sync with
#      lattice-state-home.sh by spc-282 A1.
# Prints the dir to stdout + returns 0; returns 1 if unresolved (caller fails
# CLOSED per tkt-239 when no override is set).
batch_gate_resolve_home() {
  local override="${LATTICE_BATCH_GATE_HOME:-${LATTICE_STATE_HOME:-}}"
  if [[ -n "$override" ]]; then
    printf '%s' "$override"
    return 0
  fi
  # Try the canonical helper first (single source of truth).
  local helper
  helper="$(cd "${BASH_SOURCE[0]%/*}/../../../../../skills/_lattice-lib/scripts" 2>/dev/null && pwd)/lattice-state-home.sh"
  if [[ -f "$helper" ]]; then
    local resolved
    if resolved=$(bash "$helper" 2>/dev/null); then
      printf '%s' "$resolved"
      return 0
    fi
  fi
  # INLINE fallback (same algorithm as lattice-state-home.sh).
  local git_common fingerprint state_root
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    git_common=$(git rev-parse --git-common-dir 2>/dev/null || true)
    [[ -n "$git_common" && "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  [[ -n "$git_common" ]] || return 1
  fingerprint=$(printf '%s' "$git_common" | shasum 2>/dev/null | cut -c1-12 || true)
  [[ -n "$fingerprint" ]] || fingerprint=$(printf '%s' "$git_common" | sha1sum 2>/dev/null | cut -c1-12 || true)
  [[ -n "$fingerprint" ]] || return 1
  state_root="${XDG_STATE_HOME:-$HOME/.local/state}/lattice"
  local home="$state_root/$fingerprint"
  mkdir -p "$home" 2>/dev/null || true
  printf '%s' "$home"
  return 0
}

# Returns 0 if the gate ALLOWS the merge (marker absent, or authorized-merge
# escape present). Returns 1 if the gate BLOCKS:
#   - marker present, no escape (reason="marker")
#   - tkt-239: LATTICE_BATCH_GATE_HOME is unset and the lattice home cannot be
#     resolved (reason="unresolvable-home") — an active .batch-work-active
#     marker under a misresolvable home (submodule / non-standard layout) would
#     otherwise be invisible and silently allow a merge, so the gate FAILS
#     CLOSED. The operator sets LATTICE_BATCH_GATE_HOME or runs --remove --reason.
# Sets BATCH_GATE_BLOCK_REASON to "marker" or "unresolvable-home" when blocking
# (caller prints a tailored advisory).
batch_gate_allows_merge() {
  local home marker auth reason
  BATCH_GATE_BLOCK_REASON=""
  home=$(batch_gate_resolve_home 2>/dev/null) || {
    if [[ -z "${LATTICE_BATCH_GATE_HOME:-}" ]]; then
      BATCH_GATE_BLOCK_REASON="unresolvable-home"
      return 1
    fi
    return 0
  }
  marker="${home}/${BATCH_GATE_MARKER}"
  [[ -f "$marker" ]] || return 0   # no marker → allowed
  # Human-authorized escape: a flag file whose first non-blank line is the
  # structured reason (e.g. "reason: user-authorized: batch done, merge #N").
  auth="${home}/${BATCH_GATE_AUTH}"
  if [[ -f "$auth" ]]; then
    reason=$(grep -v '^[[:space:]]*$' "$auth" 2>/dev/null | head -1 || true)
    [[ -n "$reason" ]] && return 0
  fi
  BATCH_GATE_BLOCK_REASON="marker"
  return 1   # marker present, no escape → blocked
}

# Print the block advice (rule + why + legal escape) to stdout. The caller
# routes it to stderr (strict) or wraps it as advisory JSON (advisory).
batch_gate_advice_text() {
  local home
  home=$(batch_gate_resolve_home 2>/dev/null || printf '<unresolved>')
  cat <<EOF
⛔ batch-work merge gate: the .batch-work-active marker is present at the
   Lattice runtime state dir (out-of-repo per ADR-011):
     $home/.batch-work-active
   Night-shift PRs may NOT merge while batch work is active
   (invariant: night states never reach merged).

   Rule (spc-186 A1, ADR-007, ADR-011): a bare \`gh pr merge\` is blocked while
   the marker exists. The marker lives out-of-repo (\$XDG_STATE_HOME/lattice/
   <repo-fingerprint>/) so it never leaks as untracked dirt in a fresh customer
   repo. This is a human-adjudicated red line — agents do not self-authorize
   red-line crossings; unapproved crossings are invalid (redo/rollback).

   Legal escape (human only — ADR-007 §5b/§5c):
     1. Remove the marker (the batch is done; human takes over merges), then
        run /finish-work — the merge hook allows it once the marker is gone:
          rm $home/.batch-work-active
     2. Set an authorized-merge flag with a structured reason (keeps the batch
        marker in place; trace required):
          echo 'reason: user-authorized: <why>' > $home/.batch-merge-authorized
        Record the authorization in the binder ## Decision journal
        (rule id=batch-merge-gate, reason, authorizer, timestamp); the escape
        is counted for the morning digest metric.

   finish-work removes the marker as a deliberate scripted step BEFORE merge
   (after human ack), not after — the merge hook enforces this fail-closed.
EOF
}
