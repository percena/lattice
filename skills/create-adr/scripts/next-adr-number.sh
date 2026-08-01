#!/usr/bin/env bash
# next-adr-number.sh — allocate the next 3-digit ADR number for docs/adr/.
#
# Pure read: scans the ADR folder for NNN-*.md files, prints max(NNN)+1 as a
# zero-padded 3-digit string. NOT a Lattice lineage mint — ADR is out-of-band
# (boundary rule distributed in create-spec / create-review / _lattice-lib);
# numbers stay manual 3-digit. This script never claims, writes, or reserves;
# the caller creates the file.
#
# Usage: next-adr-number.sh [--home <docs-adr-dir>]
#   --home  docs/adr directory (default: <git toplevel>/docs/adr)
# Env:  LATTICE_ADR_HOME overrides default home
#
# stdout: 3-digit zero-padded number (e.g. 028)
# exit: 0 ok | 1 home missing/empty-input | 2 next id would exceed 3 digits
set -euo pipefail

ADR_HOME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) ADR_HOME="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Error: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$ADR_HOME" ]]; then
  if [[ -n "${LATTICE_ADR_HOME:-}" ]]; then
    ADR_HOME="$LATTICE_ADR_HOME"
  else
    TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
    ADR_HOME="${TOP:-$(pwd)}/docs/adr"
  fi
fi

if [[ ! -d "$ADR_HOME" ]]; then
  echo "Error: ADR home not found: $ADR_HOME" >&2
  echo "Create it first, or pass --home <docs-adr-dir>." >&2
  exit 1
fi

# Collect existing 3-digit prefixes (NNN-*.md). Ignore template.md / README.md.
# Glob + regex (bash 3.2-safe; no mapfile). nullglob handles empty folders.
shopt -s nullglob
MAX=0
for f in "$ADR_HOME"/[0-9][0-9][0-9]-*.md; do
  b=$(basename "$f")
  [[ "$b" =~ ^([0-9]{3})- ]] || continue
  n=$((10#${BASH_REMATCH[1]}))
  (( n > MAX )) && MAX=$n
done

NEXT=$(( MAX + 1 ))
if (( NEXT > 999 )); then
  echo "Error: next ADR number $NEXT exceeds 3-digit range. Extend the scheme with a new ADR first." >&2
  exit 2
fi
printf '%03d\n' "$NEXT"
