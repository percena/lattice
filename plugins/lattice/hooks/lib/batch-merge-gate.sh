#!/usr/bin/env bash
# shellcheck disable=SC2034  # BATCH_GATE_BLOCK_REASON is set here and consumed by
#                            # the intercept-gh-pr-common.sh hook that sources this lib.
# Batch-work merge gate — spc-186 A1, ADR-007 five-piece contract.
#
# Blocks a bare `gh pr merge` while the batch-work marker is present, fail-closed
# in strict mode. The marker lives at the repo MAIN clone .lattice/.batch-work-active
# (single gate point — NOT per-worktree; one gate the human controls). Retiring
# per-worktree marker copies is the spc-186 A1 scope decision.
#
# Five pieces (ADR-007 §4 — a hard rule without all five is not done):
#   check  — batch_gate_allows_merge: is the marker present at MAIN .lattice/?
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

# Resolve the lattice home at the repo MAIN clone (not the worktree's own
# .lattice, which would re-introduce per-worktree gate drift). Priority:
#   1. LATTICE_BATCH_GATE_HOME — explicit override (tests / manual pin)
#   2. MAIN_ROOT/.lattice via `git rev-parse --git-common-dir`
# Prints the dir to stdout + returns 0; returns 1 if unresolved (caller fails OPEN).
batch_gate_resolve_home() {
  local git_common main_root
  if [[ -n "${LATTICE_BATCH_GATE_HOME:-}" ]]; then
    printf '%s' "$LATTICE_BATCH_GATE_HOME"
    return 0
  fi
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    # git < 2.31 fallback: relative rev-parse output is relative to CWD.
    git_common=$(git rev-parse --git-common-dir 2>/dev/null || true)
    [[ -n "$git_common" && "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  [[ -n "$git_common" ]] || return 1
  case "$git_common" in
    */.git) main_root="${git_common%/.git}" ;;
    */.git/*) main_root="${git_common%%/.git/*}" ;;
    *) main_root=$(git rev-parse --show-toplevel 2>/dev/null || true) ;;
  esac
  [[ -n "$main_root" && -d "$main_root/.lattice" ]] || return 1
  printf '%s/.lattice' "$main_root"
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
  cat <<'EOF'
⛔ batch-work merge gate: the .batch-work-active marker is present at the repo
   MAIN clone .lattice/ — night-shift PRs may NOT merge while batch work is
   active (invariant: night states never reach merged).

   Rule (spc-186 A1, ADR-007): a bare `gh pr merge` is blocked while the marker
   exists. This is a human-adjudicated red line — agents do not self-authorize
   red-line crossings; unapproved crossings are invalid (redo/rollback).

   Legal escape (human only — ADR-007 §5b/§5c):
     1. Remove the marker (the batch is done; human takes over merges), then
        run /finish-work — the merge hook allows it once the marker is gone:
          rm <MAIN>/.lattice/.batch-work-active
     2. Set an authorized-merge flag with a structured reason (keeps the batch
        marker in place; trace required):
          echo 'reason: user-authorized: <why>' > <MAIN>/.lattice/.batch-merge-authorized
        Record the authorization in the binder ## Decision journal
        (rule id=batch-merge-gate, reason, authorizer, timestamp); the escape
        is counted for the morning digest metric.

   finish-work removes the marker as a deliberate scripted step BEFORE merge
   (after human ack), not after — the merge hook enforces this fail-closed.
EOF
}
