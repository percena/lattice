#!/usr/bin/env bash
# claim-adr-file.sh — atomically create one NNN-kebab-title.md from the shipped
# template without overwriting an existing ADR or admitting a duplicate number.
#
# Usage:
#   claim-adr-file.sh --num 028 --slug storage-layout --template <adr.md> \
#     [--home docs/adr]
# stdout: claimed ADR path
# exit: 0 claimed | 1 invalid/conflict | 2 home/template/lock failure
set -euo pipefail

NUM=""; SLUG=""; TEMPLATE=""; ADR_HOME=""
LOCK_DIR=""; LOCK_HELD=false; TMP_FILE=""

cleanup() {
  if [[ -n "$TMP_FILE" && -e "$TMP_FILE" ]]; then
    rm -f -- "$TMP_FILE"
  fi
  if $LOCK_HELD; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --num)      NUM="$2"; shift 2 ;;
    --slug)     SLUG="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --home)     ADR_HOME="$2"; shift 2 ;;
    -h|--help)  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Error: unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$NUM" && -n "$SLUG" && -n "$TEMPLATE" ]] || {
  echo "Error: --num --slug --template required" >&2
  exit 1
}
[[ "$NUM" =~ ^[0-9]{3}$ ]] || { echo "Error: --num must be exactly 3 digits" >&2; exit 1; }
[[ "$SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
  echo "Error: --slug must be lowercase kebab-case" >&2
  exit 1
}
[[ -f "$TEMPLATE" && ! -L "$TEMPLATE" ]] || { echo "Error: template is not a regular file: $TEMPLATE" >&2; exit 2; }

if [[ -z "$ADR_HOME" ]]; then
  TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
  ADR_HOME="${TOP:-$(pwd)}/docs/adr"
fi
[[ -d "$ADR_HOME" && ! -L "$ADR_HOME" ]] || { echo "Error: ADR home not found or is symlinked: $ADR_HOME" >&2; exit 2; }
ADR_HOME=$(cd -P "$ADR_HOME" && pwd)

LOCK_DIR="$ADR_HOME/.create-adr.lock"
tries=0
until mkdir "$LOCK_DIR" 2>/dev/null; do
  (( tries += 1 ))
  if (( tries >= 100 )); then
    echo "Error: timed out waiting for ADR claim lock: $LOCK_DIR" >&2
    exit 2
  fi
  sleep 0.05
done
LOCK_HELD=true

shopt -s nullglob
MAX=0
SEEN=" "
for existing in "$ADR_HOME"/[0-9][0-9][0-9]-*.md; do
  name=$(basename "$existing")
  [[ "$name" =~ ^([0-9]{3})- ]] || continue
  prefix=${BASH_REMATCH[1]}
  case "$SEEN" in
    *" $prefix "*)
      echo "Error: ADR-$prefix is already claimed by multiple files" >&2
      exit 1 ;;
  esac
  SEEN="$SEEN$prefix "
  value=$((10#$prefix))
  (( value > MAX )) && MAX=$value
done

EXPECTED=$((MAX + 1))
if (( EXPECTED > 999 )); then
  echo "Error: next ADR number $EXPECTED exceeds 3-digit range" >&2
  exit 2
fi
EXPECTED_NUM=$(printf '%03d' "$EXPECTED")
if [[ "$NUM" != "$EXPECTED_NUM" ]]; then
  echo "Error: ADR-$NUM is not the current next number (expected $EXPECTED_NUM)" >&2
  exit 1
fi

TARGET="$ADR_HOME/${NUM}-${SLUG}.md"
TMP_FILE=$(mktemp "$ADR_HOME/.${NUM}-${SLUG}.tmp.XXXXXX") || {
  echo "Error: cannot create temporary ADR file in $ADR_HOME" >&2
  exit 2
}
cp -p "$TEMPLATE" "$TMP_FILE"

# Hard-link publication is atomic and refuses to overwrite a path created by a
# non-cooperating writer between the conflict scan and publication.
if ! ln "$TMP_FILE" "$TARGET" 2>/dev/null; then
  echo "Error: ADR target already exists: $TARGET" >&2
  exit 1
fi
rm -f -- "$TMP_FILE"
TMP_FILE=""
printf '%s\n' "$TARGET"
