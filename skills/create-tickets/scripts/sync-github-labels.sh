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
LABELS=$(cat <<'EOF'
feat|1D76DB|New user-visible capability (Lattice kind: feat)
bug|D73A4A|Incorrect behavior (Lattice kind: bug)
chore|FEF2C0|Tooling, deps, repo hygiene
docs|0075CA|Documentation only
refactor|D4C5F9|Behavior-preserving restructure
perf|F9D0C4|Performance
test|BFDADC|Tests only
spike|E4E669|Time-boxed research
epic|3E4B9E|Spec primary / umbrella parent
P0|B60205|Priority: urgent / production broken
P1|FF8C00|Priority: current milestone
P2|FBCA04|Priority: default schedulable
P3|C5DEF5|Priority: backlog / nice-to-have
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
