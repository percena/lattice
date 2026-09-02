#!/usr/bin/env bash
# Commit the staged Lattice finish set and assert the index is clean afterwards.
#
# finish-ledger.sh writes + stages the binder README and its .transition-ledger
# entry, but it does NOT commit or push (spc-297 / SKILL.md:123). The finish-work
# flow commits the staged set once after the per-binder loop. tkt-360 A2: the
# "assert the git index is clean after the commit" prose becomes a command — a
# partial commit (stranded staged changes from an interrupted loop, a held index
# lock, a gitignored ledger silently dropped by `git add`) is exactly how tkt-356
# and tkt-357 shipped a flipped binder with no ledger commit, turning dev
# artifacts CI red (transition_ledger_snapshot_mismatch).
#
# Usage:
#   finish-commit.sh --message "<commit subject + body>" [--repo <root>] [--pathspec <path>]
#   Exits 0 on a clean commit (or a nothing-to-commit no-op); 1 on a dirty
#   post-commit index or commit failure.
set -euo pipefail

MESSAGE=""
REPO_ROOT=""
PATHSPEC=".lattice"

usage() {
  cat >&2 <<'EOF'
Usage: finish-commit.sh --message "<commit subject + body>" [--repo <root>] [--pathspec <path>]
  --message    commit message (required). Pass a subject + body; the helper
               commits verbatim.
  --repo       git repo root (optional; defaults to the cwd's repo root).
  --pathspec   path to scope the post-commit clean assertion (default .lattice).
               The commit itself stages whatever is already staged (not limited
               to the pathspec); the pathspec only scopes the clean check.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message) MESSAGE="${2:-}"; shift 2 ;;
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --pathspec) PATHSPEC="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ -z "$MESSAGE" ]] && { echo "Error: --message is required" >&2; usage; }

GIT_DIR_ARGS=()
[[ -n "$REPO_ROOT" ]] && GIT_DIR_ARGS=(-C "$REPO_ROOT")
REPO_ROOT=$(git "${GIT_DIR_ARGS[@]}" rev-parse --show-toplevel 2>/dev/null || true)
[[ -z "$REPO_ROOT" ]] && { echo "Error: not a git repo (or cannot resolve root)" >&2; exit 1; }

# Nothing staged under .lattice? finish-ledger's no-binder skip path legitimately
# leaves nothing to commit — exit 0 with a note (finish does not fail on a skip).
STAGED=$(git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null || true)
if [[ -z "$STAGED" ]]; then
  echo "finish-commit: nothing staged under $REPO_ROOT; nothing to commit (finish-ledger no-binder skip?)"
  exit 0
fi

# Commit the staged set. The flow already staged binder(s) + ledger(s) via
# finish-ledger; this helper does NOT broaden the staged set — it commits what
# finish-ledger staged.
if ! git -C "$REPO_ROOT" commit -m "$MESSAGE" >&2; then
  echo "Error: finish-commit: git commit failed (held index lock? pre-commit hook?); the staged finish set was NOT committed (tkt-360 A2)" >&2
  exit 1
fi

COMMIT_OID=$(git -C "$REPO_ROOT" rev-parse HEAD)

# tkt-360 A2: the index-clean assertion is now a command. A non-empty
# `git status --porcelain -- <pathspec>` after the commit means stranded staged
# or unstaged .lattice changes — the classic partial-ledger-commit symptom. Fail
# closed so the operator investigates before pushing.
DIRTY=$(git -C "$REPO_ROOT" status --porcelain -- "$PATHSPEC" 2>/dev/null || true)
if [[ -n "$DIRTY" ]]; then
  echo "Error: finish-commit: post-commit index is NOT clean under '$PATHSPEC' (tkt-360 A2) — stranded staged/unstaged changes detected:" >&2
  printf '%s\n' "$DIRTY" | sed 's/^/    /' >&2
  echo "  recovery: investigate the stray .lattice changes; stage + amend, or reset, then re-run finish-ledger + finish-commit" >&2
  echo "  committed oid: $COMMIT_OID (the commit landed; the dirty tree is the symptom to resolve)" >&2
  exit 1
fi

echo "finish-commit: committed $COMMIT_OID (index clean under '$PATHSPEC')"
exit 0
