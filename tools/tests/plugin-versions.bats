#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATOR="$REPO_ROOT/tools/validate-plugin-versions.py"
  TMP_REPO="$(mktemp -d)"
  git -C "$TMP_REPO" init -q
  git -C "$TMP_REPO" config user.email lattice-test@example.invalid
  git -C "$TMP_REPO" config user.name 'Lattice Test'
  git -C "$TMP_REPO" config user.email test@example.com
  git -C "$TMP_REPO" config user.name Test
  mkdir -p "$TMP_REPO/.claude-plugin" \
    "$TMP_REPO/plugins/lattice/.claude-plugin" \
    "$TMP_REPO/plugins/lattice/hooks" \
    "$TMP_REPO/plugins/lattice/skills" \
    "$TMP_REPO/skills/create-pr" \
    "$TMP_REPO/skills/finish-work" \
    "$TMP_REPO/skills/_lattice-lib"
  ln -s ../../../skills/create-pr "$TMP_REPO/plugins/lattice/skills/create-pr"
  ln -s ../../../skills/finish-work "$TMP_REPO/plugins/lattice/skills/finish-work"
  ln -s ../../../skills/_lattice-lib "$TMP_REPO/plugins/lattice/skills/_lattice-lib"
  write_version 2.3.4
  printf 'base\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  printf 'base\n' >"$TMP_REPO/skills/finish-work/SKILL.md"
  printf 'base\n' >"$TMP_REPO/skills/_lattice-lib/SKILL.md"
  printf 'base\n' >"$TMP_REPO/plugins/lattice/hooks/hook.sh"
  git -C "$TMP_REPO" add .
  git -C "$TMP_REPO" commit -qm base
  BASE="$(git -C "$TMP_REPO" rev-parse HEAD)"
}

teardown() {
  rm -rf "$TMP_REPO"
}

write_version() {
  local lattice_version="$1"
  printf '{"name":"percena","plugins":[{"name":"lattice","source":"./plugins/lattice","version":"%s"}]}\n' \
    "$lattice_version" >"$TMP_REPO/.claude-plugin/marketplace.json"
  printf '{"name":"lattice","version":"%s"}\n' "$lattice_version" \
    >"$TMP_REPO/plugins/lattice/.claude-plugin/plugin.json"
}

commit_fixture() {
  git -C "$TMP_REPO" add .
  git -C "$TMP_REPO" commit -qm change
}

train_cut_fixture() {
  # Sibling train branch: its own bundled change + the version cut. Its head
  # stands in for the comparison base after the sibling PR merged.
  git -C "$TMP_REPO" checkout -q -b sibling "$BASE"
  printf 'sibling change\n' >"$TMP_REPO/skills/finish-work/SKILL.md"
  write_version 2.3.5
  commit_fixture
  SIBLING="$(git -C "$TMP_REPO" rev-parse HEAD)"
  # Train branch under test: different bundled change + the byte-identical cut.
  git -C "$TMP_REPO" checkout -q -b train "$BASE"
  printf 'train change\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  write_version 2.3.5
  commit_fixture
}

@test "release train: equal version with the identical shared cut passes" {
  train_cut_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$SIBLING"
  [ "$status" -eq 0 ]
  [[ "$output" == *"release-train cut shared with base"* ]]
  [[ "$output" == *"equal version 2.3.5 accepted"* ]]
  [[ "$output" == *"validate-plugin-versions: OK"* ]]
}

@test "release train: diverged base without a cut on head still fails equal version" {
  # Base advanced with an unrelated docs commit; head changed bundled content
  # but never touched the version files — not a train, still the strict law.
  git -C "$TMP_REPO" checkout -q -b sibling "$BASE"
  mkdir -p "$TMP_REPO/docs"
  printf 'unrelated\n' >"$TMP_REPO/docs/note.md"
  commit_fixture
  SIBLING="$(git -C "$TMP_REPO" rev-parse HEAD)"
  git -C "$TMP_REPO" checkout -q -b feature "$BASE"
  printf 'changed\n' >"$TMP_REPO/skills/_lattice-lib/SKILL.md"
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$SIBLING"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: bundled content changed without a version increment (2.3.4)"* ]]
}

@test "release train: --no-train restores the unconditional strict law" {
  train_cut_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$SIBLING" --no-train
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: bundled content changed without a version increment (2.3.5)"* ]]
}

@test "manifest and marketplace versions must match" {
  printf '{"name":"lattice","version":"2.3.5"}\n' \
    >"$TMP_REPO/plugins/lattice/.claude-plugin/plugin.json"
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"marketplace version '2.3.4' does not match manifest '2.3.5'"* ]]
}

@test "shared bundled content requires lattice version to increase" {
  printf 'changed\n' >"$TMP_REPO/skills/_lattice-lib/SKILL.md"
  write_version 2.3.4
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: bundled content changed without a version increment (2.3.4)"* ]]
}

@test "unrelated repository changes do not require plugin bumps" {
  mkdir -p "$TMP_REPO/docs"
  printf 'unrelated\n' >"$TMP_REPO/docs/note.md"
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lattice: 2.3.4 (unchanged)"* ]]
}

@test "plugin hook change requires version bump" {
  printf 'changed\n' >"$TMP_REPO/plugins/lattice/hooks/hook.sh"
  write_version 2.3.5
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --json
  [ "$status" -eq 0 ]
  json_output="$output"
  [[ "$output" == *'"cache_path": "~/.claude/plugins/cache/percena/lattice/2.3.5"'* ]]
  python3 -c 'import json,sys; p={x["name"]:x for x in json.load(sys.stdin)["plugins"]}; assert p["lattice"]["bundle_changed"] is True' <<<"$json_output"
}

@test "version-derived cache identity changes deterministically" {
  printf 'changed\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  write_version 2.3.5
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"previous_version": "2.3.4"'* ]]
  [[ "$output" == *'"cache_identity": "percena/lattice@2.3.5"'* ]]
  [[ "$output" == *'"cache_path": "~/.claude/plugins/cache/percena/lattice/2.3.5"'* ]]
}

@test "a changed bundle cannot use a lower semantic version" {
  printf 'changed\n' >"$TMP_REPO/plugins/lattice/hooks/hook.sh"
  write_version 2.3.3
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: version must increase, got 2.3.4 -> 2.3.3"* ]]
}

@test "uncommitted bundle changes are included in local validation" {
  printf 'working tree change\n' >"$TMP_REPO/skills/create-pr/SKILL.md"

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: bundled content changed without a version increment (2.3.4)"* ]]
}

@test "missing base fails closed instead of skipping change detection" {
  git -C "$TMP_REPO" branch -M feature
  run env -u PLUGIN_VERSION_BASE_REF python3 "$VALIDATOR" --repo-root "$TMP_REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no comparison base"* ]]
}

@test "zero OID base fails closed with an explicit error" {
  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref 0000000000000000000000000000000000000000
  [ "$status" -eq 1 ]
  [[ "$output" == *"zero OID"* ]]
}

@test "initial publish validates current metadata without a comparison base" {
  run env -u PLUGIN_VERSION_BASE_REF python3 "$VALIDATOR" --repo-root "$TMP_REPO" --initial-publish --json
  [ "$status" -eq 0 ]
  json_output="$output"
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["initial_publish"] is True; assert d["base_ref"] is None; assert d["plugins"][0]["cache_identity"] == "percena/lattice@2.3.4"' <<<"$json_output"
}

@test "initial publish still rejects marketplace and manifest mismatch" {
  printf '{"name":"lattice","version":"2.3.5"}\n' \
    >"$TMP_REPO/plugins/lattice/.claude-plugin/plugin.json"
  run env -u PLUGIN_VERSION_BASE_REF python3 "$VALIDATOR" --repo-root "$TMP_REPO" --initial-publish
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match manifest"* ]]
}

@test "initial publish cannot be combined with an explicit base" {
  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --initial-publish --base-ref "$BASE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "auto-detects origin/main when --base-ref is omitted" {
  git -C "$TMP_REPO" branch -M main
  git -C "$TMP_REPO" update-ref refs/remotes/origin/main "$BASE"
  git -C "$TMP_REPO" checkout -q -b feature
  printf 'changed\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  run env -u PLUGIN_VERSION_BASE_REF python3 "$VALIDATOR" --repo-root "$TMP_REPO" --json
  [ "$status" -eq 1 ]
  json_output="$output"
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["base_ref"] == "origin/main"; assert "lattice: bundled content changed without a version increment (2.3.4)" in d["errors"]' <<<"$json_output"
}

@test "prefers origin/main over a stale origin/HEAD target" {
  git -C "$TMP_REPO" branch -M main
  # origin/HEAD is stale: it still points at origin/master (the old default = BASE)
  git -C "$TMP_REPO" update-ref refs/remotes/origin/master "$BASE"
  git -C "$TMP_REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master

  # main advances past the stale HEAD, so origin/main is the real base
  write_version 2.3.5
  commit_fixture
  main_base="$(git -C "$TMP_REPO" rev-parse HEAD)"
  git -C "$TMP_REPO" update-ref refs/remotes/origin/main "$main_base"

  git -C "$TMP_REPO" checkout -q -b feature
  printf 'changed\n' >"$TMP_REPO/skills/_lattice-lib/SKILL.md"

  run env -u PLUGIN_VERSION_BASE_REF python3 "$VALIDATOR" --repo-root "$TMP_REPO" --json
  [ "$status" -eq 1 ]
  json_output="$output"
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["base_ref"] == "origin/main"; assert "lattice: bundled content changed without a version increment (2.3.5)" in d["errors"]' <<<"$json_output"
}


@test "arbitrary plugin removal fails even when plugin tree is deleted" {
  # Fail closed: simultaneous marketplace+tree drop is never intentional.
  mkdir -p "$TMP_REPO/plugins/extra/.claude-plugin" "$TMP_REPO/plugins/extra/hooks"
  printf '{"name":"extra","version":"1.0.0"}\n' >"$TMP_REPO/plugins/extra/.claude-plugin/plugin.json"
  printf 'base\n' >"$TMP_REPO/plugins/extra/hooks/hook.sh"
  printf '{"name":"percena","plugins":[{"name":"lattice","source":"./plugins/lattice","version":"2.3.4"},{"name":"extra","source":"./plugins/extra","version":"1.0.0"}]}\n' \
    >"$TMP_REPO/.claude-plugin/marketplace.json"
  git -C "$TMP_REPO" add .
  git -C "$TMP_REPO" commit -qm dual-base
  DUAL_BASE="$(git -C "$TMP_REPO" rev-parse HEAD)"

  rm -rf "$TMP_REPO/plugins/extra"
  write_version 2.3.4
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$DUAL_BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"extra: plugin was removed from the marketplace and disk without a replacement entry"* ]]
}

@test "marketplace drop without deleting plugin tree still fails" {
  mkdir -p "$TMP_REPO/plugins/extra/.claude-plugin" "$TMP_REPO/plugins/extra/hooks"
  printf '{"name":"extra","version":"1.0.0"}\n' >"$TMP_REPO/plugins/extra/.claude-plugin/plugin.json"
  printf 'base\n' >"$TMP_REPO/plugins/extra/hooks/hook.sh"
  printf '{"name":"percena","plugins":[{"name":"lattice","source":"./plugins/lattice","version":"2.3.4"},{"name":"extra","source":"./plugins/extra","version":"1.0.0"}]}\n' \
    >"$TMP_REPO/.claude-plugin/marketplace.json"
  git -C "$TMP_REPO" add .
  git -C "$TMP_REPO" commit -qm dual-base2
  DUAL_BASE="$(git -C "$TMP_REPO" rev-parse HEAD)"

  # Drop from marketplace only — leave tree
  write_version 2.3.4
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$DUAL_BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"extra: plugin was removed from the marketplace without a replacement entry"* ]]
}

@test "invalid manifest JSON at the base commit is a clean error, not a traceback" {
  printf 'not json\n' >"$TMP_REPO/plugins/lattice/.claude-plugin/plugin.json"
  git -C "$TMP_REPO" add .
  git -C "$TMP_REPO" commit -qm broken-base
  BROKEN_BASE="$(git -C "$TMP_REPO" rev-parse HEAD)"

  write_version 2.3.5
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BROKEN_BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: cannot inspect base state"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "external skill symlink fails validation" {
  rm -f "$TMP_REPO/plugins/lattice/skills/create-pr"
  ln -s /tmp/outside-lattice-skill-$$ "$TMP_REPO/plugins/lattice/skills/create-pr"
  write_version 2.3.5
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escapes repository root"* ]]
}

# tkt-114: linear-push train acceptance — integration-branch push events have
# base == merge-base, so the divergent-blob signature can never hold there.

linear_train_fixture() {
  # main = released state at 2.3.4 (BASE). dev: member-1 lands the 2.3.5 cut,
  # member-2 lands a bundled change with version files untouched (the push
  # comparison that went red on the real dev — run 33042132795).
  git -C "$TMP_REPO" branch -q main "$BASE"
  git -C "$TMP_REPO" checkout -q -b dev "$BASE"
  printf 'member-1 change\n' >"$TMP_REPO/skills/finish-work/SKILL.md"
  write_version 2.3.5
  commit_fixture
  MID="$(git -C "$TMP_REPO" rev-parse HEAD)"
  printf 'member-2 change\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  commit_fixture
}

@test "release train: linear push mid-train (base already bumped vs main) passes" {
  linear_train_fixture
  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$MID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"release-train cut shared with base"* ]]
}

@test "release train: linear push after promotion (main == base version) stays strict" {
  linear_train_fixture
  # promote: main fast-forwards to the dev tip — 2.3.5 is now released
  git -C "$TMP_REPO" checkout -q main
  git -C "$TMP_REPO" merge -q --ff-only dev
  git -C "$TMP_REPO" checkout -q dev
  PROMOTED="$(git -C "$TMP_REPO" rev-parse HEAD)"
  printf 'post-release change\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  commit_fixture
  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$PROMOTED"
  [ "$status" -eq 1 ]
  [[ "$output" == *"without a version increment"* ]]
}

@test "release train: linear push with --no-train stays strict" {
  linear_train_fixture
  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$MID" --no-train
  [ "$status" -eq 1 ]
}
