#!/usr/bin/env bash
# Print absolute path to _lattice-lib/scripts (library install-unit). Exit 1 if missing.
# Usage: LIB=$(bash resolve-lattice-lib.sh [--from DIR])
#
# --from is retained as a compatibility-only argument. It is deliberately not
# searched: the resolver's installed directory is the trust anchor, never the
# consumer repository or caller-controlled cwd.
#
# Resolve order:
#   1. Absolute LATTICE_LIB_SCRIPTS env (explicit operator override)
#   2. This script's own canonical directory
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) [[ $# -ge 2 ]] || { echo "Error: --from requires a directory" >&2; exit 2; }; shift 2 ;;
    *) echo "Error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "${LATTICE_LIB_SCRIPTS:-}" ]]; then
  if [[ "$LATTICE_LIB_SCRIPTS" != /* || ! -f "$LATTICE_LIB_SCRIPTS/_lattice-home.sh" ]]; then
    echo "Error: LATTICE_LIB_SCRIPTS must be an absolute installed _lattice-lib/scripts directory" >&2
    exit 1
  fi
  printf '%s\n' "$(cd "$LATTICE_LIB_SCRIPTS" && pwd -P)"
  exit 0
fi

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$SELF_DIR/_lattice-home.sh" ]]; then
  printf '%s\n' "$SELF_DIR"
  exit 0
fi

echo "Error: resolver is not installed inside _lattice-lib/scripts; reinstall the full skill pack or set an absolute LATTICE_LIB_SCRIPTS" >&2
exit 1
