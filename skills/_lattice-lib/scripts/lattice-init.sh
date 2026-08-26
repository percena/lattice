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
#   <root>/.lattice/gitignore.snippet    (idempotent; only rewritten on change)
#   <root>/.lattice/README.md            (if missing; short pointer)
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
    "$LATTICE/gitignore.snippet" \
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
profile: ${PROFILE}
EOF
  CREATED_CONFIG=true
fi

SNIPPET_FILE="$LATTICE/gitignore.snippet"
# Idempotent write: only touch the file when content actually differs, so
# re-runs don't churn mtimes or surface as stray git diffs. The snippet is a
# merge helper (transient), not a tracked artifact — it ignores itself below so
# consumer repos that merge the block also stop tracking it.
SNIPPET_TMP=$(mktemp "${TMPDIR:-/tmp}/lattice-snippet.XXXXXX")
cat >"$SNIPPET_TMP" <<'EOF'
# --- Lattice (generated by lattice-init.sh; merge into repo .gitignore) ---
.lattice/tickets/**/assets/*
!.lattice/tickets/**/assets/.gitkeep
.lattice/.ids/
.lattice/**/.*.tmp
.lattice/lineage/
.lattice/BOARD.md
# Regenerated merge helper — never commit; ignore it once merged.
.lattice/gitignore.snippet
# Optional: physical worktrees if you override WORKTREE_ROOT in-repo
.worktrees/
# --- end Lattice ---
EOF
assert_managed_paths_safe
if [[ -f "$SNIPPET_FILE" ]] && cmp -s "$SNIPPET_FILE" "$SNIPPET_TMP"; then
  rm -f "$SNIPPET_TMP"
else
  mv -f "$SNIPPET_TMP" "$SNIPPET_FILE"
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
  # Also treat pre-existing Lattice ignore rules as "already merged" so ensure
  # does not double-append when the marker comment was hand-written differently.
  ALREADY=false
  if [[ -f "$GI" ]]; then
    if grep -qF "$MARKER" "$GI" 2>/dev/null; then
      ALREADY=true
    elif grep -qE '(^|/)\.lattice/(lineage/|BOARD\.md|\.ids/)' "$GI" 2>/dev/null; then
      ALREADY=true
    fi
  fi
  if ! $ALREADY; then
    assert_managed_paths_safe
    {
      echo ""
      cat "$SNIPPET_FILE"
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
  python3 - "$LATTICE" "$CREATED_CONFIG" "$CREATED_README" "$GITIGNORE_WROTE" "$LABELS_RAN" "$LABELS_MSG" "$ACTIVE_PROFILE" "$ROOT" <<'PY'
import json, sys
lattice, cc, cr, gw, lr, lm, prof, root = sys.argv[1:9]
print(json.dumps({
  "ok": True,
  "root": root,
  "lattice": lattice,
  "created_config": cc == "true",
  "created_readme": cr == "true",
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
  echo "  snippet:  $SNIPPET_FILE"
  echo "  readme:   created=$CREATED_README"
  echo "  gitignore write: $GITIGNORE_WROTE"
  echo "  labels:   $LABELS_MSG"
  if ! $WRITE_GITIGNORE; then
    echo "  tip: merge gitignore.snippet into .gitignore, or re-run with --write-gitignore"
  fi
  echo "  next: /start-work  (or resume tkt-N / spc-N)"
fi
