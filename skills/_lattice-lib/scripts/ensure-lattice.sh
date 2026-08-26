#!/usr/bin/env bash
# Ensure a consumer repo is Lattice-ready (idempotent).
#
# Product contract: agents call this at skill entry. Users never run it.
# Prefer this over lattice-init.sh from skills — lattice-init is the
# low-level writer; ensure is the entrypoint (check + init-if-needed).
#
# Usage:
#   ensure-lattice.sh [--root <repo>] [--profile strict|light]
#                     [--sync-labels] [--write-gitignore|--no-write-gitignore]
#                     [--check-only] [--json]
#
# Behaviour:
#   - Resolves root: --root | git toplevel | $PWD
#   - --check-only: exit 0 if .lattice/config.yaml + skeleton dirs exist; else 1
#   - default: run lattice-init.sh (idempotent). Default passes --write-gitignore
#     unless --no-write-gitignore. Does not overwrite existing config/profile.
#   - --sync-labels: forwarded to lattice-init (opt-in; not default)
#   - --profile: only applies when config is first created
#   - scaffolds .lattice/preferences.md from the shipped template when absent
#     (heredoc fallback on partial installs; NEVER overwrites an existing file)
#
# Exit: 0 ok/ready, 1 error or not ready (--check-only), 2 usage
set -euo pipefail

ROOT=""
PROFILE=""
SYNC_LABELS=false
WRITE_GITIGNORE=true
CHECK_ONLY=false
AS_JSON=false

usage() {
  cat >&2 <<'EOF'
Usage: ensure-lattice.sh [--root <repo>] [--profile strict|light]
                         [--sync-labels] [--write-gitignore|--no-write-gitignore]
                         [--check-only] [--json]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --sync-labels) SYNC_LABELS=true; shift ;;
    --write-gitignore) WRITE_GITIGNORE=true; shift ;;
    --no-write-gitignore) WRITE_GITIGNORE=false; shift ;;
    --check-only) CHECK_ONLY=true; shift ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ -n "$PROFILE" ]]; then
  PROFILE=$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  case "$PROFILE" in
    strict|light) ;;
    *) echo "Error: --profile must be strict or light" >&2; exit 1 ;;
  esac
fi

if [[ -z "$ROOT" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ROOT=$(git rev-parse --show-toplevel)
  else
    ROOT=$PWD
  fi
fi
# --check-only is a read-only probe: never create the root as a side effect.
# A missing root then simply reports not-ready via the check block below.
if ! $CHECK_ONLY; then
  mkdir -p "$ROOT"
fi
if RESOLVED=$(cd "$ROOT" 2>/dev/null && pwd); then
  ROOT="$RESOLVED"
fi

LATTICE="$ROOT/.lattice"
CONFIG="$LATTICE/config.yaml"

_skeleton_ok() {
  [[ -f "$CONFIG" ]] \
    && [[ -d "$LATTICE/specs" ]] \
    && [[ -d "$LATTICE/reviews" ]] \
    && [[ -d "$LATTICE/tickets" ]]
}

_read_profile() {
  if [[ -f "$CONFIG" ]]; then
    grep -E '^[[:space:]]*profile:' "$CONFIG" 2>/dev/null \
      | head -1 \
      | sed -E 's/^[[:space:]]*profile:[[:space:]]*//' \
      | tr -d '[:space:]' || true
  fi
}

if $CHECK_ONLY; then
  READY=false
  if _skeleton_ok; then
    READY=true
  fi
  ACTIVE_PROFILE=$(_read_profile || true)
  if $AS_JSON; then
    python3 - "$ROOT" "$LATTICE" "$READY" "${ACTIVE_PROFILE:-}" <<'PY'
import json, sys
root, lattice, ready, prof = sys.argv[1:5]
print(json.dumps({
  "ok": ready == "true",
  "ready": ready == "true",
  "root": root,
  "lattice": lattice,
  "action": "check",
  "profile": prof or None,
}, indent=2))
PY
  else
    if $READY; then
      echo "ensure-lattice: ready"
      echo "  root:    $ROOT"
      echo "  lattice: $LATTICE"
      [[ -n "${ACTIVE_PROFILE:-}" ]] && echo "  profile: $ACTIVE_PROFILE"
    else
      echo "ensure-lattice: not ready (missing .lattice/config.yaml or skeleton dirs)" >&2
      echo "  root: $ROOT" >&2
    fi
  fi
  if $READY; then
    exit 0
  fi
  exit 1
fi

# Resolve the physical installed script directory, including when the
# entrypoint itself was reached through a symlink (same pattern as
# lattice-init.sh resolve_script_dir): the lexical BASH_SOURCE directory would
# let a consumer checkout place a fake lattice-init.sh / references tree
# beside a symlink to this trusted script.
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
INIT="$SCRIPT_DIR/lattice-init.sh"
if [[ ! -f "$INIT" ]]; then
  echo "Error: lattice-init.sh not found next to ensure-lattice.sh" >&2
  echo "  Install the full Lattice pack (_lattice-lib + six user skills):" >&2
  echo "  npx skills add percena/lattice -a claude-code -a codex -g -y" >&2
  exit 1
fi

HAD_CONFIG=false
[[ -f "$CONFIG" ]] && HAD_CONFIG=true

INIT_ARGS=(--root "$ROOT")
$WRITE_GITIGNORE && INIT_ARGS+=(--write-gitignore)
$SYNC_LABELS && INIT_ARGS+=(--sync-labels)
[[ -n "$PROFILE" ]] && INIT_ARGS+=(--profile "$PROFILE")
$AS_JSON && INIT_ARGS+=(--json)

# Keep stdout vs stderr separate so --json is not poisoned by warnings.
INIT_ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/ensure-lattice.XXXXXX.err")
set +e
INIT_OUT=$(bash "$INIT" "${INIT_ARGS[@]}" 2>"$INIT_ERR_FILE")
INIT_STATUS=$?
set -e
INIT_ERR=$(cat "$INIT_ERR_FILE" 2>/dev/null || true)
rm -f "$INIT_ERR_FILE"

if [[ -n "$INIT_ERR" ]]; then
  printf '%s\n' "$INIT_ERR" >&2
fi

if [[ $INIT_STATUS -ne 0 ]]; then
  echo "Error: Lattice ensure failed (lattice-init exit $INIT_STATUS)" >&2
  echo "  Install the full Lattice pack if scripts are missing:" >&2
  echo "  npx skills add percena/lattice -a claude-code -a codex -g -y" >&2
  [[ -n "$INIT_OUT" ]] && printf '%s\n' "$INIT_OUT" >&2
  exit 1
fi

if ! _skeleton_ok; then
  echo "Error: ensure-lattice finished but skeleton still incomplete under $LATTICE" >&2
  exit 1
fi

# --- .lattice/preferences.md scaffold (spc-42 A3, ADR-004 §3) ---------------
# Idempotent: NEVER overwrite an existing file — team edits are the point.
# Source of truth is the skill-shipped template; when the references tree is
# absent (partial consumer install), a minimal heredoc fallback keeps the
# scaffold working. Not part of _skeleton_ok: pre-existing repos stay "ready"
# under --check-only and pick the file up lazily on their next default run.
PREFS="$LATTICE/preferences.md"
PREFS_CREATED=false
if [[ -L "$PREFS" ]]; then
  # Consumer checkouts are input, not trusted (matches lattice-init's
  # managed-path rule): never write through a symlink.
  echo "Error: refusing symlinked managed path: $PREFS" >&2
  exit 1
fi
if [[ ! -e "$PREFS" ]]; then
  PREFS_TEMPLATE="$SCRIPT_DIR/../references/templates/preferences.md"
  if [[ -f "$PREFS_TEMPLATE" ]]; then
    cp "$PREFS_TEMPLATE" "$PREFS"
  else
    cat >"$PREFS" <<'EOF'
# Team preferences (Lattice)

Taste/stack defaults for unattended agents — chain source #4 in `decision-policy.md`.
Severity per `constraint-language.md`: INVARIANT conflicts park, DEFAULT applies + journals, HINT just applies.
Lifecycle: entries promote from decision-journal items ratified ×2 (proposal in the
morning digest); supersede with a date, never delete; Spec/ADR always outrank
preferences; every use is cited in the consuming agent's `## Decision journal`.

## INVARIANT

<!-- - No new runtime dependency without an ADR (added YYYY-MM-DD) -->

## DEFAULT

<!-- - New scripts: bash + `set -euo pipefail` (added YYYY-MM-DD) -->

## HINT

<!-- - Prefer table-form reference docs over prose lists (added YYYY-MM-DD) -->
EOF
  fi
  PREFS_CREATED=true
fi

ACTION="ready"
if ! $HAD_CONFIG; then
  ACTION="initialized"
fi

ACTIVE_PROFILE=$(_read_profile || true)
[[ -z "${ACTIVE_PROFILE:-}" ]] && ACTIVE_PROFILE="${PROFILE:-strict}"

if $AS_JSON; then
  if printf '%s' "$INIT_OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
    printf '%s' "$INIT_OUT" | python3 -c '
import json, sys
action, prof, prefs = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(sys.stdin)
data["action"] = action
data["ready"] = True
data["ok"] = True
data["created_preferences"] = prefs == "true"
if not data.get("profile"):
    data["profile"] = prof
print(json.dumps(data, indent=2))
' "$ACTION" "$ACTIVE_PROFILE" "$PREFS_CREATED"
  else
    python3 - "$ROOT" "$LATTICE" "$ACTION" "$ACTIVE_PROFILE" "$PREFS_CREATED" <<'PY'
import json, sys
root, lattice, action, prof, prefs = sys.argv[1:6]
print(json.dumps({
  "ok": True,
  "ready": True,
  "action": action,
  "root": root,
  "lattice": lattice,
  "profile": prof,
  "created_preferences": prefs == "true",
}, indent=2))
PY
  fi
else
  if [[ "$ACTION" == "initialized" ]]; then
    echo "ensure-lattice: initialized"
  else
    echo "ensure-lattice: ready"
  fi
  echo "  root:    $ROOT"
  echo "  lattice: $LATTICE"
  echo "  profile: $ACTIVE_PROFILE"
  echo "  action:  $ACTION"
  echo "  prefs:   created=$PREFS_CREATED"
  if printf '%s' "$INIT_OUT" | grep -q 'labels:'; then
    printf '%s\n' "$INIT_OUT" | grep -E 'labels:|gitignore write:' | sed 's/^/  init: /' || true
  fi
fi

exit 0
