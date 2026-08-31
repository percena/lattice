#!/usr/bin/env bash
# Bootstrap a consumer repo for Lattice.
#
# Idempotent: safe to re-run. Low-level writer — prefer ensure-lattice.sh as the
# agent entrypoint. Does not create a 7th user skill. Users never run this.
#
# Usage:
#   lattice-init.sh [--root <repo-path>] [--profile strict|light]
#                   [--sync-labels] [--write-gitignore] [--json]
#
# Creates:
#   <root>/.lattice/{specs,reviews,tickets}
#   <root>/.lattice/config.yaml          (if missing; default profile: strict)
#   <root>/.lattice/README.md            (if missing; short pointer)
# The Lattice ignore block is emitted inline (to .gitignore via
# --write-gitignore, or to stdout otherwise); no persistent snippet file.
#
# --sync-labels     run create-tickets sync-github-labels.sh when discoverable
# --write-gitignore append snippet block to <root>/.gitignore if markers absent
# --profile X       set profile when writing config.yaml (default strict)
#
# Exit: 0 ok, 1 error, 2 usage
set -euo pipefail

ROOT=""
PROFILE="strict"
SYNC_LABELS=false
WRITE_GITIGNORE=false
AS_JSON=false

usage() {
  cat >&2 <<'EOF'
Usage: lattice-init.sh [--root <repo>] [--profile strict|light]
                       [--sync-labels] [--write-gitignore] [--json]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --sync-labels) SYNC_LABELS=true; shift ;;
    --write-gitignore) WRITE_GITIGNORE=true; shift ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

PROFILE=$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
case "$PROFILE" in
  strict|light) ;;
  *) echo "Error: --profile must be strict or light" >&2; exit 1 ;;
esac

# --json renders via python3: preflight BEFORE any state mutation so a missing
# interpreter cannot leave .lattice/ or .gitignore half-written and exit 127
# (style matches ensure-workspace.sh preflight).
if $AS_JSON && ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required by lattice-init.sh --json" >&2
  exit 1
fi

# Resolve the physical installed script directory, including when the entrypoint
# itself was reached through a symlink. Using the lexical BASH_SOURCE directory
# here would let a consumer checkout recreate a fake sibling skill tree beside
# a symlink to this trusted script.
resolve_script_dir() {
  local source="$1"
  local dir target
  while [[ -L "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    target="$(readlink "$source")"
    if [[ "$target" == /* ]]; then
      source="$target"
    else
      source="$dir/$target"
    fi
  done
  cd -P "$(dirname "$source")" && pwd
}
SCRIPT_DIR="$(resolve_script_dir "${BASH_SOURCE[0]}")"

if [[ -z "$ROOT" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ROOT=$(git rev-parse --show-toplevel)
  else
    ROOT=$PWD
  fi
fi
mkdir -p "$ROOT"
ROOT=$(cd "$ROOT" && pwd -P)

LATTICE="$ROOT/.lattice"

# Consumer repositories are input, not part of the trusted installed package.
# Refuse every managed symlink before the first mutation so a checkout cannot
# redirect initialization into an arbitrary user-writable path. Re-check the
# paths immediately before later writes to narrow local check/write races.
assert_managed_paths_safe() {
  local path
  for path in \
    "$LATTICE" \
    "$LATTICE/specs" \
    "$LATTICE/reviews" \
    "$LATTICE/tickets" \
    "$LATTICE/config.yaml" \
    "$LATTICE/README.md" \
    "$LATTICE/preferences.md"
  do
    if [[ -L "$path" ]]; then
      echo "Error: refusing symlinked managed path: $path" >&2
      return 1
    fi
  done
  if $WRITE_GITIGNORE && [[ -L "$ROOT/.gitignore" ]]; then
    echo "Error: refusing symlinked managed path: $ROOT/.gitignore" >&2
    return 1
  fi
}

assert_managed_paths_safe
mkdir -p "$LATTICE/specs" "$LATTICE/reviews" "$LATTICE/tickets"
assert_managed_paths_safe

CREATED_CONFIG=false
if [[ ! -f "$LATTICE/config.yaml" ]]; then
  assert_managed_paths_safe
  cat >"$LATTICE/config.yaml" <<EOF
# Lattice consumer config. Safe to commit.
# profile: strict (default) | light
#   strict — sibling worktree default for shippable; alignment HARD on open Acceptance
#   light  — shippable --mode branch allowed; alignment softens Acceptance HARD → WARN
#            bind law still requires tkt-/spc- (no unbound)
# Override for one shell: export LATTICE_PROFILE=light
# long_lived_patterns: [integration, trunk]   # additive to main/master/dev/develop/release/*/rc/*
# batch-work tunables (flat keys; all DEFAULT — absent = defaults shown):
# batch_timebox_S: 30        # per-ticket wall-clock timebox, minutes, mode S
# batch_timebox_M: 60        # mode M
# batch_timebox_C: 120       # mode C
# batch_fuse_threshold: 50   # layer failed+stuck percentage that trips the fuse
profile: ${PROFILE}
EOF
  CREATED_CONFIG=true
fi

# Lattice ignore policy (ADR-011 / spc-282 A3). Two layers, one source of truth
# per directory:
#   1. .lattice/.gitignore (TRACKED, committed) — the single source of truth for
#      the .lattice/ temp subclass (atomic-write temps, derived indexes, id
#      claims). Runtime gate markers + coordinator relocated OUT of repo to
#      $XDG_STATE_HOME/lattice/<fingerprint>/ (ADR-011), so they no longer need a
#      gitignore entry here.
#   2. root .gitignore inline block — only NON-.lattice entries (the .worktrees/
#      defensive override). Previously this block also carried .lattice/** entries
#      which duplicated .lattice/.gitignore; de-duplicated going forward.
# Previously materialized as .lattice/gitignore.snippet (spc-277) — eliminated
# in favor of inline emission; now split into the two layers above.
lattice_dotlattice_gitignore() {
  cat <<'EOF'
# --- Lattice .lattice/ temp subclass (tracked; ADR-011 / spc-282 A3) ---
# Pure runtime state (batch markers, coordinator, ledger .lock) relocated
# OUT of repo to $XDG_STATE_HOME/lattice/<repo-fingerprint>/ — these are the
# residual co-located temps that must stay for atomic writes + derived indexes.
**/.*.tmp
.ids/
.transition-ledger/*.lock
tickets/**/assets/*
!tickets/**/assets/.gitkeep
lineage/
BOARD.md
# --- end Lattice .lattice/ temp subclass ---
EOF
}

lattice_adr_gitignore() {
  cat <<'EOF'
# --- Lattice docs/adr/ temp subclass (tracked; ADR-011 / spc-282 A4) ---
# ADR atomic-write temps + mutex lock dirs. These must stay co-located with
# their target (os.replace/mv atomicity requires same filesystem); the tracked
# gitignore keeps them out of git status. EXIT traps in claim-adr-file.sh +
# append-adr-index-row.sh unlink them on exit/signal; this is the crash-leak guard.
.create-adr.lock/
README.lock/
.*.tmp*
# --- end Lattice docs/adr/ temp subclass ---
EOF
}

lattice_root_ignore_block() {
  cat <<'EOF'
# --- Lattice (generated by lattice-init.sh; merge into repo .gitignore) ---
# .lattice/ temp subclass lives in .lattice/.gitignore (single source of truth).
# Optional: physical worktrees if you override WORKTREE_ROOT in-repo
.worktrees/
# --- end Lattice ---
EOF
}

# One-shot migration: remove a stray .lattice/gitignore.snippet left by an
# older install so it stops surfacing as an untracked file. rm -f on a symlink
# only unlinks, never the target.
rm -f "$LATTICE/gitignore.snippet"

# Write the tracked .lattice/.gitignore (the .lattice/ temp subclass) — the
# single source of truth for .lattice/ temp files. Idempotent (marker-guarded);
# never overwrites a hand-edited file that already carries the marker.
CREATED_DOTLATTICE_GITIGNORE=false
if $WRITE_GITIGNORE && [[ ! -f "$LATTICE/.gitignore" ]]; then
  assert_managed_paths_safe
  lattice_dotlattice_gitignore >"$LATTICE/.gitignore"
  CREATED_DOTLATTICE_GITIGNORE=true
elif $WRITE_GITIGNORE && [[ -f "$LATTICE/.gitignore" ]] \
  && ! grep -qF "# --- Lattice .lattice/ temp subclass" "$LATTICE/.gitignore" 2>/dev/null; then
  # Existing .lattice/.gitignore without the Lattice block — append idempotently.
  assert_managed_paths_safe
  { echo ""; lattice_dotlattice_gitignore; } >>"$LATTICE/.gitignore"
  CREATED_DOTLATTICE_GITIGNORE=true
fi

# Write the tracked docs/adr/.gitignore (the ADR temp subclass) — keeps ADR
# atomic-write temps + mutex lock dirs out of git status. Idempotent
# (marker-guarded). Only when docs/adr/ exists (create-adr creates it on first
# ADR; lattice-init ensures .lattice/ but not necessarily docs/adr/).
CREATED_ADR_GITIGNORE=false
ADR_DIR="$ROOT/docs/adr"
if $WRITE_GITIGNORE && [[ -d "$ADR_DIR" ]] && [[ ! -f "$ADR_DIR/.gitignore" ]]; then
  assert_managed_paths_safe
  lattice_adr_gitignore >"$ADR_DIR/.gitignore"
  CREATED_ADR_GITIGNORE=true
elif $WRITE_GITIGNORE && [[ -d "$ADR_DIR" ]] && [[ -f "$ADR_DIR/.gitignore" ]] \
  && ! grep -qF "# --- Lattice docs/adr/ temp subclass" "$ADR_DIR/.gitignore" 2>/dev/null; then
  assert_managed_paths_safe
  { echo ""; lattice_adr_gitignore; } >>"$ADR_DIR/.gitignore"
  CREATED_ADR_GITIGNORE=true
fi

CREATED_README=false
if [[ ! -f "$LATTICE/README.md" ]]; then
  assert_managed_paths_safe
  cat >"$LATTICE/README.md" <<'EOF'
# `.lattice/` (Lattice binders)

Active Specs, Reviews, and ticket binders for this repo.

- **Ready-check:** agents run `ensure-lattice.sh` (not a user command)
- **Config:** `config.yaml` (`profile: strict|light`)
- **Bloodline:** Spec/binder edges + GitHub `Fixes`/`Refs`. No derived global index or BOARD.

See skill `start-work` portable policy and monorepo `docs/getting-started.md` when available.
EOF
  CREATED_README=true
fi

GITIGNORE_WROTE=false
if $WRITE_GITIGNORE; then
  GI="$ROOT/.gitignore"
  assert_managed_paths_safe
  MARKER="# --- Lattice (generated by lattice-init.sh"
  # The root block is "already merged" only if the ROOT .gitignore already
  # carries the marker. The .lattice/.gitignore layer is independent (written
  # above) and must NOT suppress the root block write on a first run.
  ALREADY=false
  if [[ -f "$GI" ]] && grep -qF "$MARKER" "$GI" 2>/dev/null; then
    ALREADY=true
  fi
  if ! $ALREADY; then
    assert_managed_paths_safe
    {
      echo ""
      lattice_root_ignore_block
    } >>"$GI"
    GITIGNORE_WROTE=true
  fi
fi

LABELS_RAN=false
LABELS_MSG="skipped"
if $SYNC_LABELS; then
  SYNC="${SCRIPT_DIR}/../../create-tickets/scripts/sync-github-labels.sh"
  if [[ ! -f "$SYNC" ]]; then
    LABELS_MSG="sync script not found (install create-tickets beside _lattice-lib)"
    echo "Warning: $LABELS_MSG" >&2
  else
    if (cd "$ROOT" && bash "$SYNC"); then
      LABELS_RAN=true
      LABELS_MSG="ok"
    else
      LABELS_MSG="sync failed (gh auth?)"
      echo "Warning: $LABELS_MSG" >&2
    fi
  fi
fi

# Report active profile if helper available
ACTIVE_PROFILE="$PROFILE"
if [[ -f "$SCRIPT_DIR/_lattice-home.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/_lattice-home.sh"
  export LATTICE_HOME="$LATTICE"
  ACTIVE_PROFILE=$(lattice_profile 2>/dev/null || echo "$PROFILE")
fi

if $AS_JSON; then
  python3 - "$LATTICE" "$CREATED_CONFIG" "$CREATED_README" "$CREATED_DOTLATTICE_GITIGNORE" "$CREATED_ADR_GITIGNORE" "$GITIGNORE_WROTE" "$LABELS_RAN" "$LABELS_MSG" "$ACTIVE_PROFILE" "$ROOT" <<'PY'
import json, sys
lattice, cc, cr, dlg, dag, gw, lr, lm, prof, root = sys.argv[1:11]
print(json.dumps({
  "ok": True,
  "root": root,
  "lattice": lattice,
  "created_config": cc == "true",
  "created_readme": cr == "true",
  "created_dotlattice_gitignore": dlg == "true",
  "created_adr_gitignore": dag == "true",
  "gitignore_wrote": gw == "true",
  "labels_ran": lr == "true",
  "labels_msg": lm,
  "profile": prof,
}, indent=2))
PY
else
  echo "lattice-init: ok"
  echo "  root:     $ROOT"
  echo "  lattice:  $LATTICE"
  echo "  config:   $LATTICE/config.yaml (created=$CREATED_CONFIG)"
  echo "  profile:  $ACTIVE_PROFILE"
  echo "  readme:   created=$CREATED_README"
  echo "  gitignore write: $GITIGNORE_WROTE"
  echo "  labels:   $LABELS_MSG"
  if ! $WRITE_GITIGNORE; then
    echo "  tip: re-run with --write-gitignore to auto-write both ignore layers,"
    echo "       or merge the blocks below manually:"
    echo "  --- .lattice/.gitignore (tracked; the .lattice/ temp subclass) ---"
    lattice_dotlattice_gitignore
    echo "  --- root .gitignore (non-.lattice entries only) ---"
    lattice_root_ignore_block
  fi
  echo "  next: /start-work  (or resume tkt-N / spc-N)"
fi
