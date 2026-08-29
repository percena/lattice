#!/usr/bin/env bats
# bats tests for check-installed-skill-drift.sh (tkt-196)
#
# Verifies the installed-skill-tree drift check fails LOUD (exit 1, never a
# silent exit 2) with an actionable, bidirectional inventory on mismatch, and
# exits 0 when in sync. The check must NEVER write to the install (no blind
# clobber), even when install-only files are present.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export CHECK="$REPO_ROOT/skills/_lattice-lib/scripts/check-installed-skill-drift.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/drift.XXXXXX")"
  export TEST_DIR
  export REPO_SKILLS="$TEST_DIR/repo"
  export INST_SKILLS="$TEST_DIR/inst"
  mkdir -p "$REPO_SKILLS/start-work" "$REPO_SKILLS/create-pr"
  # identical baseline on both sides
  mkdir -p "$INST_SKILLS/start-work" "$INST_SKILLS/create-pr"
  printf 'skill body\n' >"$REPO_SKILLS/start-work/SKILL.md"
  printf 'skill body\n' >"$INST_SKILLS/start-work/SKILL.md"
  printf 'pr body\n' >"$REPO_SKILLS/create-pr/SKILL.md"
  printf 'pr body\n' >"$INST_SKILLS/create-pr/SKILL.md"
  printf 'flow\n' >"$REPO_SKILLS/create-pr/references/flow.md" 2>/dev/null || \
    { mkdir -p "$REPO_SKILLS/create-pr/references"; printf 'flow\n' >"$REPO_SKILLS/create-pr/references/flow.md"; }
  mkdir -p "$INST_SKILLS/create-pr/references"; printf 'flow\n' >"$INST_SKILLS/create-pr/references/flow.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_check() {
  LATTICE_SKILL_ROOT="$REPO_SKILLS" LATTICE_INSTALLED_SKILL_HOME="$INST_SKILLS" \
    run bash "$CHECK" "$@"
}

@test "in-sync install exits 0 and reports in sync" {
  run_check
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qiE 'in sync'
}

@test "repo-only file is reported and exits 1 (not 2)" {
  printf 'new\n' >"$REPO_SKILLS/start-work/new-script.sh"   # absent from install
  run_check
  [ "$status" -eq 1 ]          # loud, never 2
  printf '%s\n' "$output" | grep -qF 'start-work/new-script.sh'
  printf '%s\n' "$output" | grep -qiE 'repo-only'
}

@test "differing content is reported and exits 1 (not 2)" {
  printf 'stale\n' >"$INST_SKILLS/start-work/SKILL.md"      # content mismatch
  run_check
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'start-work/SKILL.md'
  printf '%s\n' "$output" | grep -qiE 'differs'
}

@test "install-only file is reported bidirectionally and is NOT clobbered" {
  printf 'local-edit\n' >"$INST_SKILLS/start-work/local-edit.md"  # absent from repo
  run_check
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'start-work/local-edit.md'
  printf '%s\n' "$output" | grep -qiE 'install-only'
  # the script never writes: the local-edit file must survive the check
  [ -f "$INST_SKILLS/start-work/local-edit.md" ]
  [ "$(cat "$INST_SKILLS/start-work/local-edit.md")" = "local-edit" ]
}

@test "whole skill absent from install is reported as skill-absent-install" {
  mkdir -p "$REPO_SKILLS/review-delivery"
  printf 'body\n' >"$REPO_SKILLS/review-delivery/SKILL.md"   # no install counterpart
  run_check
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qiE 'skill-absent-install'
  printf '%s\n' "$output" | grep -qF 'review-delivery'
}

@test "generated __pycache__ / *.pyc is ignored (not reported as drift)" {
  mkdir -p "$INST_SKILLS/create-pr/__pycache__"
  printf 'bytecode\n' >"$INST_SKILLS/create-pr/__pycache__/x.pyc"
  run_check
  [ "$status" -eq 0 ]                                # bytecode is not source
  ! printf '%s\n' "$output" | grep -qF '__pycache__/x.pyc'
}

@test "actionable refresh hint points at docs/getting-started" {
  printf 'stale\n' >"$INST_SKILLS/start-work/SKILL.md"
  run_check
  printf '%s\n' "$output" | grep -qF 'docs/getting-started.md'
  printf '%s\n' "$output" | grep -qiE 'Refresh'
  printf '%s\n' "$output" | grep -qF 'npx skills add'
}

@test "drift exits 1 never 2 across all mismatch shapes" {
  # combine all shapes at once
  printf 'new\n' >"$REPO_SKILLS/start-work/new.sh"          # repo-only
  printf 'stale\n' >"$INST_SKILLS/start-work/SKILL.md"     # differs
  printf 'local\n' >"$INST_SKILLS/start-work/local.md"      # install-only
  run_check
  [ "$status" -eq 1 ]
  [ "$status" -ne 2 ]
}

@test "non-Lattice skill in install is out of scope (not flagged)" {
  mkdir -p "$INST_SKILLS/bailian-cli"; printf 'x\n' >"$INST_SKILLS/bailian-cli/SKILL.md"
  run_check
  [ "$status" -eq 0 ]   # install-side extra skills are not Lattice skills -> ignored
  ! printf '%s\n' "$output" | grep -qF 'bailian-cli'
}

@test "--json drift payload is valid and lists categories" {
  printf 'new\n' >"$REPO_SKILLS/start-work/new.sh"
  printf 'stale\n' >"$INST_SKILLS/start-work/SKILL.md"
  printf 'local\n' >"$INST_SKILLS/start-work/local.md"
  run_check --json
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"drift":true'
  printf '%s\n' "$output" | grep -qF '"repo_only":["start-work/new.sh"]'
  printf '%s\n' "$output" | grep -qF '"differs":["start-work/SKILL.md"]'
  printf '%s\n' "$output" | grep -qF '"install_only":["start-work/local.md"]'
}

@test "--json in-sync payload reports drift:false" {
  run_check --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"drift":false'
}

@test "bad argument exits 2 with usage hint" {
  run bash "$CHECK" --bogus
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qiE 'unknown argument'
}

@test "missing skill root exits 2 loudly (never silent)" {
  run bash "$CHECK" --skill-root /no/such/dir --installed-dir "$INST_SKILLS"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qiE 'repo skill root not found'
}

@test "missing installed home exits 2 loudly (never silent)" {
  run bash "$CHECK" --skill-root "$REPO_SKILLS" --installed-dir /no/such/dir
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qiE 'installed skill home not found'
}
