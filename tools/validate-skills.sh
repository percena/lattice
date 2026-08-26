#!/usr/bin/env bash
# Tier-1 skill lint.
# - User-facing skills must have anatomy footers (Rationalizations / Red Flags / Verification)
# - Lifecycle six must ship evals/evals.json
# - Frontmatter must include name + description
# _lattice-lib is internal library install-unit and exempt from anatomy/evals.
set -euo pipefail

# This file lives at monorepo tools/validate-skills.sh.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${LATTICE_SKILLS_DIR:-${ROOT}/skills}"
ERR=0

# Print only the YAML frontmatter block (between the leading `---` pair).
# Frontmatter keys must be checked here, not with whole-file/head greps that
# body prose could satisfy or contaminate.
frontmatter() {
  awk 'NR==1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
       /^---[[:space:]]*$/ { exit }
       { print }' "$1"
}

USER_FACING=(
  start-work
  create-spec
  create-review
  create-tickets
  create-pr
  finish-work
  generate-wiki
  review-code
  review-production
  review-delivery
  create-adr
)

LIFECYCLE_SIX=(
  start-work
  create-spec
  create-review
  create-tickets
  create-pr
  finish-work
)

# Optional quality side-paths — anatomy required; lifecycle evals.json not required
QUALITY_SIDE_PATHS=(
  review-code
  review-production
  review-delivery
)

need_heading() {
  local file="$1" heading="$2"
  if ! grep -qE "^## ${heading}\$" "$file"; then
    echo "ERROR: $file missing heading: ## $heading" >&2
    ERR=1
  fi
}

for name in "${USER_FACING[@]}"; do
  f="${SKILLS_DIR}/${name}/SKILL.md"
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing $f" >&2
    ERR=1
    continue
  fi
  # frontmatter
  if ! frontmatter "$f" | grep -qE '^name:'; then
    echo "ERROR: $f missing frontmatter name:" >&2
    ERR=1
  fi
  if ! frontmatter "$f" | grep -qE '^description:'; then
    echo "ERROR: $f missing frontmatter description:" >&2
    ERR=1
  fi
  need_heading "$f" "Common Rationalizations"
  need_heading "$f" "Red Flags"
  need_heading "$f" "Verification"
done

# Codex cross-agent invariants: the "claude-code,codex" claim is
# advertised in every SKILL.md but was never machine-checked. Two invariants
# keep the claim honest and prevent silent regression:
#   1. Every user-facing skill (+ the _lattice-lib install-unit) that declares
#      metadata.agents must list `codex` — no skill may advertise Claude-only
#      while README/architecture promise a cross-agent baseline.
#   2. Shared skill bodies/references must not use plugin-root or cwd-relative
#      executable fallbacks. Hosts resolve the active SKILL.md directory as an
#      absolute skill root; Claude may expose CLAUDE_SKILL_DIR, while portable
#      clients can set LATTICE_SKILL_ROOT from the loaded skill path.
CODEX_UNITS=("${USER_FACING[@]}" _lattice-lib)
for name in "${CODEX_UNITS[@]}"; do
  f="${SKILLS_DIR}/${name}/SKILL.md"
  [[ -f "$f" ]] || continue
  # metadata.agents line (frontmatter only); tolerate quoting/spacing
  agents_line=$(frontmatter "$f" | grep -E '^[[:space:]]*agents:' | head -1 || true)
  if [[ -z "$agents_line" ]]; then
    echo "ERROR: $f missing metadata.agents (declare \"claude-code,codex\")" >&2
    ERR=1
  elif [[ "$agents_line" != *codex* ]]; then
    echo "ERROR: $f metadata.agents does not list codex ($agents_line) — cross-agent baseline requires it or drop the claim" >&2
    ERR=1
  fi
done

# No CLAUDE_PLUGIN_ROOT in any shared skill body or reference (Codex has no
# plugin root). Search SKILL.md + references/ across all skills; scripts/ too.
if grep -rn --include='SKILL.md' --include='*.md' --include='*.sh' "CLAUDE_PLUGIN_ROOT" "$SKILLS_DIR" 2>/dev/null; then
  echo "ERROR: CLAUDE_PLUGIN_ROOT found in shared skill content (portable skills resolve from their absolute skill root)" >&2
  ERR=1
fi

# Never turn an unset host variable into the consumer cwd, and never execute a
# repository-relative fallback as if it were installed skill code.
if grep -rnF --include='SKILL.md' --include='*.md' --include='*.sh' '${CLAUDE_SKILL_DIR:-.}' "$SKILLS_DIR" 2>/dev/null; then
  echo 'ERROR: unsafe ${CLAUDE_SKILL_DIR:-.} fallback found; fail closed on a missing absolute skill root' >&2
  ERR=1
fi
if grep -rnF --include='SKILL.md' --include='*.md' '="skills/_lattice-lib/scripts/' "$SKILLS_DIR" 2>/dev/null; then
  echo "ERROR: cwd-relative skills/_lattice-lib/scripts executable fallback found" >&2
  ERR=1
fi
# Shared runtime scripts must not discover executable helpers below a consumer
# repository root either. Installed sibling skills are trusted package code;
# $ROOT/skills belongs to the checkout and is attacker-controlled input.
if grep -rnE --include='*.sh' '(\$\{ROOT\}|\$ROOT)/skills/[^[:space:]]+/scripts/' "$SKILLS_DIR" 2>/dev/null; then
  echo "ERROR: consumer-root skill script executable fallback found" >&2
  ERR=1
fi

for name in "${LIFECYCLE_SIX[@]}"; do
  ev="${SKILLS_DIR}/${name}/evals/evals.json"
  if [[ ! -f "$ev" ]]; then
    echo "ERROR: lifecycle skill missing evals: $ev" >&2
    ERR=1
  fi
done

# Gate skills must keep at least one pressure-* behavioral case
PRESSURE_GATES=(start-work create-pr finish-work create-spec create-tickets create-review)
for name in "${PRESSURE_GATES[@]}"; do
  ev="${SKILLS_DIR}/${name}/evals/evals.json"
  if [[ ! -f "$ev" ]]; then
    continue
  fi
  if ! grep -qE '"id"[[:space:]]*:[[:space:]]*"pressure-' "$ev"; then
    echo "ERROR: $ev missing pressure-* case id (gate skill requires ≥1)" >&2
    ERR=1
  fi
done

# _lattice-lib should exist but is exempt
if [[ ! -f "${SKILLS_DIR}/_lattice-lib/SKILL.md" ]]; then
  echo "ERROR: _lattice-lib/SKILL.md missing" >&2
  ERR=1
fi

if [[ ! -f "${SKILLS_DIR}/_lattice-lib/references/orchestration-patterns.md" ]]; then
  echo "ERROR: _lattice-lib/references/orchestration-patterns.md missing" >&2
  ERR=1
fi

# Quality side-paths must stay optional: present skills need anatomy (via USER_FACING);
# document that lifecycle routing catalog remains six-only.
for name in "${QUALITY_SIDE_PATHS[@]}"; do
  f="${SKILLS_DIR}/${name}/SKILL.md"
  if [[ ! -f "$f" ]]; then
    echo "ERROR: quality side-path missing $f" >&2
    ERR=1
  fi
done

if [[ "$ERR" -ne 0 ]]; then
  echo "validate-skills: FAILED" >&2
  exit 1
fi
echo "validate-skills: OK (${#USER_FACING[@]} user-facing skills, ${#LIFECYCLE_SIX[@]} lifecycle evals, ${#PRESSURE_GATES[@]} pressure gates, ${#QUALITY_SIDE_PATHS[@]} quality side-paths)"
