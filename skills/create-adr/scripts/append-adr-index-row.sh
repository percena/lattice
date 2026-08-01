#!/usr/bin/env bash
# append-adr-index-row.sh — idempotently append a row to the docs/adr/README.md
# status index table.
#
# ADRs are out-of-band (boundary rule, see create-spec / create-review policy);
# the README index table is the only cold-reader scan map. Hand-maintained
# tables drift (a row can exist on disk while the table stopped at an earlier
# number). This script fixes that by appending the row deterministically and
# skipping when a row for the same number already exists.
#
# Usage:
#   append-adr-index-row.sh --num 028 --file docs/adr/028-foo.md \
#     --title "Title" --status Active [--supersede "Superseded by [029](…)"]
#   [--readme docs/adr/README.md] [--dry-run]
# Exit: 0 appended or already-present | 1 usage | 2 README/table not found
set -euo pipefail

NUM=""; FILE=""; TITLE=""; STATUS=""; SUPERSEDE=""; README=""; DRY=false
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
    --num)       NUM="$2"; shift 2 ;;
    --file)      FILE="$2"; shift 2 ;;
    --title)     TITLE="$2"; shift 2 ;;
    --status)    STATUS="$2"; shift 2 ;;
    --supersede) SUPERSEDE="$2"; shift 2 ;;
    --readme)    README="$2"; shift 2 ;;
    --dry-run)   DRY=true; shift ;;
    -h|--help)   sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Error: unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$NUM" && -n "$FILE" && -n "$TITLE" && -n "$STATUS" ]] || { echo "Error: --num --file --title --status required" >&2; exit 1; }

# Input sanitization (fail closed). The README index is a markdown table; a
# literal '|', backslash, or newline in a cell would corrupt the row (extra
# columns) or be mangled by awk -v escape interpretation. Reject these rather
# than silently emitting a broken table.
validate_cell() {
  case "$1" in
    *"|"* | *"\\"* | *$'\n'* | *$'\r'*)
      echo "Error: --$2 contains '|', backslash, or newline — cannot be a single index-table cell" >&2
      exit 1 ;;
  esac
}
[[ "$NUM" =~ ^[0-9]{3}$ ]] || { echo "Error: --num must be exactly 3 digits (got '$NUM'); use next-adr-number.sh" >&2; exit 1; }
validate_cell "$TITLE" title
validate_cell "$STATUS" status
[[ -z "$SUPERSEDE" ]] || validate_cell "$SUPERSEDE" supersede

[[ -f "$FILE" && ! -L "$FILE" ]] || { echo "Error: ADR file not found or is symlinked: $FILE" >&2; exit 1; }
BASENAME=$(basename "$FILE")
[[ "$BASENAME" =~ ^${NUM}-[a-z0-9]+(-[a-z0-9]+)*\.md$ ]] || {
  echo "Error: --file basename must be ${NUM}-<lowercase-kebab-title>.md (got '$BASENAME')" >&2
  exit 1
}

# Resolve README path
if [[ -z "$README" ]]; then
  FDIR=$(dirname "$FILE")
  README="$FDIR/README.md"
fi
[[ -f "$README" && ! -L "$README" ]] || { echo "Error: README not found or is symlinked: $README" >&2; exit 2; }

FILE_DIR=$(cd -P "$(dirname "$FILE")" && pwd)
README_DIR=$(cd -P "$(dirname "$README")" && pwd)
[[ "$FILE_DIR" == "$README_DIR" ]] || {
  echo "Error: ADR file and README must be in the same directory" >&2
  exit 1
}

if [[ -z "$SUPERSEDE" ]]; then
  SUPERSEDE_CELL="—"
else
  SUPERSEDE_CELL="$SUPERSEDE"
fi

NEW_ROW="| [$NUM](./$BASENAME) | $TITLE | $STATUS | $SUPERSEDE_CELL |"

# Locate the index table block. The table's header line is the first line
# matching `| ADR |` (intro tables that do not contain that header are
# skipped). We append after the last contiguous pipe-prefixed row of that table,
# before the next blank/prose/heading line (or at EOF).
HEADER_RE='^[[:space:]]*\|[[:space:]]*ADR[[:space:]]*\|'

# Find header line number
HDR=$(grep -nE "$HEADER_RE" "$README" | head -1 | cut -d: -f1 || true)
if [[ -z "$HDR" ]]; then
  echo "Error: index table header '| ADR |' not found in $README" >&2
  exit 2
fi

# Serialize the complete conflict-check + read-modify-replace transaction.
LOCK_DIR="$README.lock"
tries=0
until mkdir "$LOCK_DIR" 2>/dev/null; do
  (( tries += 1 ))
  if (( tries >= 100 )); then
    echo "Error: timed out waiting for ADR index lock: $LOCK_DIR" >&2
    exit 2
  fi
  sleep 0.05
done
LOCK_HELD=true

# Fail closed if two files claim the same number. This re-check happens under
# the lock so cooperating create-adr callers cannot both report success.
shopt -s nullglob
numbered_files=("$FILE_DIR"/"$NUM"-*.md)
if (( ${#numbered_files[@]} != 1 )) || [[ "$(basename "${numbered_files[0]}")" != "$BASENAME" ]]; then
  echo "Error: ADR-$NUM must map to exactly one file named $BASENAME" >&2
  exit 1
fi

ROW_COUNT=$(grep -cE "^[[:space:]]*\|[[:space:]]*\[$NUM\]\(" "$README" || true)
if (( ROW_COUNT > 1 )); then
  echo "Error: multiple README rows already claim ADR-$NUM" >&2
  exit 1
fi
if (( ROW_COUNT == 1 )); then
  EXISTING_ROW=$(grep -E "^[[:space:]]*\|[[:space:]]*\[$NUM\]\(" "$README" | head -1)
  if printf '%s\n' "$EXISTING_ROW" | grep -Fq "[$NUM](./$BASENAME)"; then
    echo "already-present: row for ADR-$NUM exists in $README"
    exit 0
  fi
  echo "Error: README row for ADR-$NUM points at a different file" >&2
  exit 1
fi

if $DRY; then
  echo "[dry-run] would insert in $README:"
  echo "$NEW_ROW"
  exit 0
fi

TMP_FILE=$(mktemp "$README_DIR/.README.md.tmp.XXXXXX") || {
  echo "Error: cannot create temporary README in $README_DIR" >&2
  exit 2
}
cp -p "$README" "$TMP_FILE"

# Insert before the first non-table line after the ADR header. This handles a
# blank separator, an immediately following heading, or EOF without moving the
# row into later prose.
awk -v new="$NEW_ROW" '
  BEGIN { seen=0; in_table=0; inserted=0 }
  !seen && /^[[:space:]]*\|[[:space:]]*ADR[[:space:]]*\|/ {
    seen=1; in_table=1; print; next
  }
  in_table && /^[[:space:]]*\|/ { print; next }
  in_table && !inserted { print new; inserted=1; in_table=0 }
  { print }
  END { if (seen && !inserted) print new }
' "$README" > "$TMP_FILE"
mv "$TMP_FILE" "$README"
TMP_FILE=""
echo "appended: $NEW_ROW"
