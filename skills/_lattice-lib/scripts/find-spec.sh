#!/usr/bin/env bash
# Resolve a Lattice Spec file path by number, regardless of slug.
#
# Usage:
#   find-spec.sh --id N [--home <lattice home>]
#
#   --id N|spc-N   spec number (bare decimal)
#   --home DIR     lattice home (default: <git toplevel>/.lattice, else $PWD/.lattice)
#
# Prints the path of <home>/specs/spc-N-<slug>.md or the slugless spc-N.md.
# Exact-N match only: spc-4 never matches spc-42 (the two globs pin the char
# after N to `-` or `.md`). Mirrors the candidate order used by
# build-review-context.sh --spec so both resolve identically.
#
# Exit: 0 found (path on stdout), 1 absent/ambiguous (stderr), 2 usage
set -euo pipefail

ID=""
HOME_DIR=""

usage() {
  cat >&2 <<'EOF'
Usage: find-spec.sh --id N [--home <lattice home>]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ -n "$ID" ]] || usage
ID="${ID#spc-}"
if ! [[ "$ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --id wants N or spc-N (bare decimal, got '$ID')" >&2
  exit 2
fi

if [[ -z "$HOME_DIR" ]]; then
  if ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    HOME_DIR="$ROOT/.lattice"
  else
    HOME_DIR="$PWD/.lattice"
  fi
fi

SPECS_DIR="$HOME_DIR/specs"
if [[ ! -d "$SPECS_DIR" ]]; then
  echo "Error: specs dir not found: $SPECS_DIR" >&2
  exit 1
fi

MATCHES=()
for cand in "$SPECS_DIR/spc-$ID-"*.md "$SPECS_DIR/spc-$ID.md"; do
  [[ -f "$cand" ]] && MATCHES+=("$cand")
done

if [[ ${#MATCHES[@]} -eq 0 ]]; then
  echo "Error: spec spc-$ID not found under $SPECS_DIR" >&2
  exit 1
fi
if [[ ${#MATCHES[@]} -gt 1 ]]; then
  echo "Error: spec spc-$ID is ambiguous under $SPECS_DIR:" >&2
  printf '  %s\n' "${MATCHES[@]}" >&2
  exit 1
fi

printf '%s\n' "${MATCHES[0]}"
