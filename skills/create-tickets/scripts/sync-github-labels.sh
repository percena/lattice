#!/usr/bin/env bash
# Create Lattice kind + priority labels on the current GitHub repo (idempotent).
# Usage:
#   sync-github-labels.sh [--force-color]
# Env: GH_REPO or gh default repo from cwd
set -euo pipefail

FORCE=false
if [[ "${1:-}" == "--force-color" ]]; then
  FORCE=true
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI required" >&2
  exit 1
fi

# name|color|description
# Canon = live label set (docs/github-surface.md §1, ratified default tkt-65):
# kinds map feat→enhancement, docs→documentation; refactor/perf/test/spike
# file under chore. No P0 — urgent work is P1 with the urgency in the body.
LABELS=$(cat <<'EOF'
bug|D73A4A|Something is not working (Lattice kind: bug)
documentation|0075CA|Improvements or additions to documentation (Lattice kind: docs)
enhancement|A2EEEF|New feature or request (Lattice kind: feat)
chore|C5DEF5|Maintenance / non-feature work
epic|5319E7|Spec primary / multi-ticket epic
spec|0E8A16|Lattice Spec (spc-N)
adr|BFD4F2|Architecture Decision Record
P1|B60BF0|Priority 1 (high)
P2|BFD4F2|Priority 2 (medium)
P3|EAEAEA|Priority 3 (low)
EOF
)

created=0
updated=0
skipped=0

# Fetch the existing label set once, fully paginated — a fixed --limit cap
# would misroute existing labels into `gh label create` (422) on huge repos.
# A failure here must abort loudly rather than misroute every label.
if ! EXISTING=$(gh api --paginate 'repos/{owner}/{repo}/labels' --jq '.[].name'); then
  echo "Error: gh api repos/{owner}/{repo}/labels failed (auth/network?); aborting without changes" >&2
  exit 1
fi

while IFS='|' read -r name color desc; do
  [[ -z "$name" ]] && continue
  # -F: label names are literal strings, not regexes
  if grep -qxF -- "$name" <<< "$EXISTING"; then
    if $FORCE; then
      gh label edit "$name" --color "$color" --description "$desc" >/dev/null
      updated=$((updated + 1))
      echo "updated: $name"
    else
      skipped=$((skipped + 1))
      echo "exists:  $name"
    fi
  else
    gh label create "$name" --color "$color" --description "$desc" >/dev/null
    created=$((created + 1))
    echo "created: $name"
  fi
done <<< "$LABELS"

echo "done created=$created updated=$updated skipped=$skipped"
