#!/usr/bin/env bash
# migrate-relocated-runtime-state.sh — one-shot cleanup of in-repo runtime
# state files superseded by the ADR-011 / spc-282 relocation.
#
# Before ADR-011, the batch-work gate markers (.batch-work-active,
# .batch-merge-authorized) and the coordinator spine (.coordinator/) lived
# in-repo under .lattice/. They are now relocated OUT of repo to
# $XDG_STATE_HOME/lattice/<repo-fingerprint>/ (spc-282 A1/A2). Any clone that
# ran batch-work before the upgrade may still carry the dead in-repo copies as
# untracked dirt. This migration removes them (read-then-delete; runtime state,
# no data loss).
#
# Idempotent: rm -f on absent files is a no-op. Called by ensure-lattice.sh on
# every ready-check (cheap — only touches files if present). Does NOT touch the
# committed transition-ledger .jsonl (that stays in-repo by design).
set -euo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ROOT=$(git rev-parse --show-toplevel)
  else
    ROOT=$PWD
  fi
fi
LATTICE="$ROOT/.lattice"
[[ -d "$LATTICE" ]] || exit 0

REMOVED=0
# Stale in-repo gate markers (now at the state home).
for f in "$LATTICE/.batch-work-active" "$LATTICE/.batch-merge-authorized"; do
  if [[ -e "$f" ]]; then
    rm -f "$f" && REMOVED=$((REMOVED+1))
  fi
done
# Stale in-repo coordinator spine dir (now at the state home).
if [[ -d "$LATTICE/.coordinator" ]]; then
  rm -rf "$LATTICE/.coordinator" && REMOVED=$((REMOVED+1))
fi
# Stale in-repo transition-ledger .lock sidecars (now at the state home; the
# .jsonl stays committed). Only remove .lock files, never the .jsonl.
if [[ -d "$LATTICE/.transition-ledger" ]]; then
  while IFS= read -r -d '' lk; do
    rm -f "$lk" && REMOVED=$((REMOVED+1))
  done < <(find "$LATTICE/.transition-ledger" -name '*.lock' -print0 2>/dev/null || true)
fi

if [[ $REMOVED -gt 0 ]]; then
  echo "migrate-relocated-runtime-state: removed $REMOVED stale in-repo runtime-state file(s)/dir(s) under $LATTICE (relocated to state home per ADR-011 / spc-282)" >&2
fi
exit 0
