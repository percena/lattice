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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
action, prof = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
data["action"] = action
data["ready"] = True
data["ok"] = True
if not data.get("profile"):
    data["profile"] = prof
print(json.dumps(data, indent=2))
' "$ACTION" "$ACTIVE_PROFILE"
  else
    python3 - "$ROOT" "$LATTICE" "$ACTION" "$ACTIVE_PROFILE" <<'PY'
import json, sys
root, lattice, action, prof = sys.argv[1:5]
print(json.dumps({
  "ok": True,
  "ready": True,
  "action": action,
  "root": root,
  "lattice": lattice,
  "profile": prof,
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
  if printf '%s' "$INIT_OUT" | grep -q 'labels:'; then
    printf '%s\n' "$INIT_OUT" | grep -E 'labels:|gitignore write:' | sed 's/^/  init: /' || true
  fi
fi

exit 0
