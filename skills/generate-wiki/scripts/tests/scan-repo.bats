#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  SCAN="$REPO_ROOT/skills/generate-wiki/scripts/scan-repo.sh"
  FIXTURE="$(mktemp -d)"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email lattice-test@example.invalid
  git -C "$FIXTURE" config user.name 'Lattice Test'
  mkdir -p "$FIXTURE/src" "$FIXTURE/docs" "$FIXTURE/wiki" "$FIXTURE/.lattice" "$FIXTURE/node_modules/pkg"
  touch "$FIXTURE/src/app.py" "$FIXTURE/src/view.tsx" "$FIXTURE/src/widget.svelte"
  touch "$FIXTURE/docs/one.md" "$FIXTURE/docs/two.md" "$FIXTURE/README.md"
  touch "$FIXTURE/wiki/generated.md" "$FIXTURE/.lattice/private.md" "$FIXTURE/node_modules/pkg/readme.md"
}

teardown() {
  rm -rf "$FIXTURE"
}

report_value() {
  local heading="$1"
  awk -v heading="### $heading" '$0 == heading { getline; print; exit }' <<<"$output"
}

@test "source count excludes Markdown and reports it separately" {
  run bash -c 'cd "$1" && bash "$2"' _ "$FIXTURE" "$SCAN"
  [ "$status" -eq 0 ]
  [ "$(report_value source-file-count-approx)" -eq 3 ]
  [ "$(report_value markdown-file-count-approx)" -eq 3 ]
}
