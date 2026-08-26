#!/usr/bin/env bats
# Tests for validate-skills.sh frontmatter scoping.
# Uses LATTICE_SKILLS_DIR to point the validator at a generated fixture tree.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export VALIDATE="$REPO_ROOT/tools/validate-skills.sh"
}

setup() {
  TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/validate-skills.XXXXXX")"
  export LATTICE_SKILLS_DIR="$TEST_TMP/skills"
  build_green_tree
}

teardown() {
  rm -rf "${TEST_TMP:?}"
}

write_skill_md() {
  # $1 path
  cat >"$1" <<'EOF'
---
name: fixture
description: fixture skill
metadata:
  agents: "claude-code,codex"
---

# Fixture

## Common Rationalizations

## Red Flags

## Verification
EOF
}

build_green_tree() {
  local user_facing="start-work create-spec create-review create-tickets create-pr finish-work batch-work run-e2e generate-wiki review-code review-production create-adr review-delivery"
  local lifecycle="start-work create-spec create-review create-tickets create-pr finish-work"
  local name
  for name in $user_facing _lattice-lib; do
    mkdir -p "$LATTICE_SKILLS_DIR/$name"
    write_skill_md "$LATTICE_SKILLS_DIR/$name/SKILL.md"
  done
  for name in $lifecycle; do
    mkdir -p "$LATTICE_SKILLS_DIR/$name/evals"
    printf '{"cases":[{"id":"pressure-fixture"}]}\n' >"$LATTICE_SKILLS_DIR/$name/evals/evals.json"
  done
  mkdir -p "$LATTICE_SKILLS_DIR/_lattice-lib/references"
  : >"$LATTICE_SKILLS_DIR/_lattice-lib/references/orchestration-patterns.md"
}

# Mirror the repo layout beside the fixture skills root: a plugins/lattice/skills
# tree of 3-level relative symlinks, so the registration-integrity bundle check
# activates (it keys off dirname of the skills root).
build_plugin_tree() {
  local dir name
  mkdir -p "$TEST_TMP/plugins/lattice/skills"
  for dir in "$LATTICE_SKILLS_DIR"/*/; do
    name="$(basename "$dir")"
    ln -s "../../../skills/$name" "$TEST_TMP/plugins/lattice/skills/$name"
  done
}

@test "green fixture tree passes" {
  run bash "$VALIDATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"validate-skills: OK"* ]]
}

@test "name: in body prose cannot satisfy the frontmatter check" {
  f="$LATTICE_SKILLS_DIR/start-work/SKILL.md"
  cat >"$f" <<'EOF'
---
description: fixture skill
metadata:
  agents: "claude-code,codex"
---
name: sneaky-body-line

## Common Rationalizations

## Red Flags

## Verification
EOF
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing frontmatter name:"* ]]
}

@test "agents: in body prose cannot satisfy the codex check" {
  f="$LATTICE_SKILLS_DIR/create-pr/SKILL.md"
  cat >"$f" <<'EOF'
---
name: create-pr
description: fixture skill
---

Body prose mentioning supported
agents: "claude-code,codex" must not count.

## Common Rationalizations

## Red Flags

## Verification
EOF
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing metadata.agents"* ]]
}

@test "description: below the closing --- cannot satisfy the check" {
  f="$LATTICE_SKILLS_DIR/review-code/SKILL.md"
  cat >"$f" <<'EOF'
---
name: review-code
metadata:
  agents: "claude-code,codex"
---
description: not-frontmatter (line 6, inside old head -n 30 window)

## Common Rationalizations

## Red Flags

## Verification
EOF
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing frontmatter description:"* ]]
}

@test "missing codex in frontmatter agents still fails" {
  f="$LATTICE_SKILLS_DIR/finish-work/SKILL.md"
  cat >"$f" <<'EOF'
---
name: finish-work
description: fixture skill
metadata:
  agents: "claude-code"
---

## Common Rationalizations

## Red Flags

## Verification
EOF
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not list codex"* ]]
}

@test "cwd fallback through an unset CLAUDE_SKILL_DIR fails" {
  printf '\nRun "${CLAUDE_SKILL_DIR:-.}/scripts/helper.sh"\n' >>"$LATTICE_SKILLS_DIR/start-work/SKILL.md"
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsafe ${CLAUDE_SKILL_DIR:-.} fallback'* ]]
}

@test "consumer-repository lattice-lib executable fallback fails" {
  printf '\nRESOLVE="skills/_lattice-lib/scripts/resolve-lattice-lib.sh"\n' >>"$LATTICE_SKILLS_DIR/create-pr/SKILL.md"
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cwd-relative skills/_lattice-lib/scripts"* ]]
}

@test "unregistered skills/ directory fails registration integrity" {
  mkdir -p "$LATTICE_SKILLS_DIR/rogue-skill"
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skills/rogue-skill not registered"* ]]
}

@test "full plugin bundle passes; a missing bundle symlink fails" {
  build_plugin_tree
  run bash "$VALIDATE"
  [ "$status" -eq 0 ]
  rm "$TEST_TMP/plugins/lattice/skills/batch-work"
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plugin bundle missing symlink for skills/batch-work"* ]]
}

@test "consumer-root runtime helper fallback fails" {
  mkdir -p "$LATTICE_SKILLS_DIR/_lattice-lib/scripts"
  cat >"$LATTICE_SKILLS_DIR/_lattice-lib/scripts/unsafe.sh" <<'EOF'
#!/usr/bin/env bash
SYNC="${ROOT}/skills/create-tickets/scripts/sync-github-labels.sh"
bash "$SYNC"
EOF
  run bash "$VALIDATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"consumer-root skill script executable fallback"* ]]
}
