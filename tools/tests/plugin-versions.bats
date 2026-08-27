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

# --- ADR-005: release-boundary enforcement (dev lenient / release strict) ---

@test "dev mode: bundled change with equal version passes (no --release-check)" {
  printf 'changed\n' >"$TMP_REPO/skills/_lattice-lib/SKILL.md"
  write_version 2.3.4
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lattice: 2.3.4 (changed)"* ]]
  [[ "$output" == *"validate-plugin-versions: OK"* ]]
}

@test "release check: bundled change with equal version fails (--release-check)" {
  printf 'changed\n' >"$TMP_REPO/skills/_lattice-lib/SKILL.md"
  write_version 2.3.4
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --release-check
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: bundled content changed without a version increment (2.3.4)"* ]]
}

@test "release check: bundled change with version bump passes (--release-check)" {
  printf 'changed\n' >"$TMP_REPO/skills/_lattice-lib/SKILL.md"
  write_version 2.3.5
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --release-check
  [ "$status" -eq 0 ]
  [[ "$output" == *"validate-plugin-versions: OK"* ]]
}

@test "non-decrease enforced in dev mode (version must not go backwards)" {
  printf 'changed\n' >"$TMP_REPO/plugins/lattice/hooks/hook.sh"
  write_version 2.3.3
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: version must increase, got 2.3.4 -> 2.3.3"* ]]
}

@test "non-decrease enforced in release check mode" {
  printf 'changed\n' >"$TMP_REPO/plugins/lattice/hooks/hook.sh"
  write_version 2.3.3
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --release-check
  [ "$status" -eq 1 ]
  [[ "$output" == *"lattice: version must increase, got 2.3.4 -> 2.3.3"* ]]
}

# --- existing behavioral tests (updated for release-boundary model) ---

@test "manifest and marketplace versions must match" {
  printf '{"name":"lattice","version":"2.3.5"}\n' \
    >"$TMP_REPO/plugins/lattice/.claude-plugin/plugin.json"
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"marketplace version '2.3.4' does not match manifest '2.3.5'"* ]]
}

@test "unrelated repository changes do not require plugin bumps" {
  mkdir -p "$TMP_REPO/docs"
  printf 'unrelated\n' >"$TMP_REPO/docs/note.md"
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lattice: 2.3.4 (unchanged)"* ]]
}

@test "plugin hook change requires version bump at release boundary" {
  printf 'changed\n' >"$TMP_REPO/plugins/lattice/hooks/hook.sh"
  write_version 2.3.5
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --release-check --json
  [ "$status" -eq 0 ]
  json_output="$output"
  [[ "$output" == *'"cache_path": "~/.claude/plugins/cache/percena/lattice/2.3.5"'* ]]
  python3 -c 'import json,sys; p={x["name"]:x for x in json.load(sys.stdin)["plugins"]}; assert p["lattice"]["bundle_changed"] is True' <<<"$json_output"
}

@test "version-derived cache identity changes deterministically" {
  printf 'changed\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  write_version 2.3.5
  commit_fixture

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --release-check --json
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

@test "uncommitted bundle changes are included in local validation (dev mode passes)" {
  printf 'working tree change\n' >"$TMP_REPO/skills/create-pr/SKILL.md"

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lattice: 2.3.4 (changed)"* ]]
}

@test "uncommitted bundle changes fail at release boundary" {
  printf 'working tree change\n' >"$TMP_REPO/skills/create-pr/SKILL.md"

  run python3 "$VALIDATOR" --repo-root "$TMP_REPO" --base-ref "$BASE" --release-check
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

@test "auto-detects origin/main when --base-ref is omitted (dev mode: lenient)" {
  git -C "$TMP_REPO" branch -M main
  git -C "$TMP_REPO" update-ref refs/remotes/origin/main "$BASE"
  git -C "$TMP_REPO" checkout -q -b feature
  printf 'changed\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  run env -u PLUGIN_VERSION_BASE_REF python3 "$VALIDATOR" --repo-root "$TMP_REPO" --json
  [ "$status" -eq 0 ]
  json_output="$output"
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["base_ref"] == "origin/main"; assert d["release_check"] is False' <<<"$json_output"
}

@test "auto-detects origin/main with --release-check (strict)" {
  git -C "$TMP_REPO" branch -M main
  git -C "$TMP_REPO" update-ref refs/remotes/origin/main "$BASE"
  git -C "$TMP_REPO" checkout -q -b feature
  printf 'changed\n' >"$TMP_REPO/skills/create-pr/SKILL.md"
  run env -u PLUGIN_VERSION_BASE_REF python3 "$VALIDATOR" --repo-root "$TMP_REPO" --release-check --json
  [ "$status" -eq 1 ]
  json_output="$output"
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["base_ref"] == "origin/main"; assert d["release_check"] is True; assert "lattice: bundled content changed without a version increment (2.3.4)" in d["errors"]' <<<"$json_output"
}

@test "prefers origin/main over a stale origin/HEAD target (dev mode: lenient)" {
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
  [ "$status" -eq 0 ]
  json_output="$output"
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["base_ref"] == "origin/main"; assert d["release_check"] is False' <<<"$json_output"
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
