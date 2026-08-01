#!/usr/bin/env bats
# lattice-lib resolve (wrappers removed)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export REPO_ROOT
  export LIB_INIT="$REPO_ROOT/skills/_lattice-lib/scripts/lattice-init.sh"
  export LIB_UP="$REPO_ROOT/skills/_lattice-lib/scripts/upload-github-asset.sh"
}

@test "lattice-init in lattice-lib is executable" {
  [ -x "$LIB_INIT" ]
  TMP=$(mktemp -d)
  run bash "$LIB_INIT" --root "$TMP" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok": true'* ]] || [[ "$output" == *'"ok":true'* ]]
  [[ -f "$TMP/.lattice/config.yaml" ]]
  rm -rf "$TMP"
}

@test "resolve-lattice-lib.sh finds monorepo scripts" {
  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/resolve-lattice-lib.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/skills/_lattice-lib/scripts"* ]]
  [[ -f "$output/_lattice-home.sh" ]]
}

@test "resolve-lattice-lib.sh does not accept legacy lattice-lib dir name" {
  # migration window closed — only _lattice-lib + LATTICE_LIB_SCRIPTS
  # Isolate: copy resolver out of monorepo package so its own dir is not a hit.
  TMP=$(mktemp -d)
  mkdir -p "$TMP/skills/start-work" "$TMP/skills/lattice-lib/scripts" "$TMP/bin"
  cp "$REPO_ROOT/skills/_lattice-lib/scripts/resolve-lattice-lib.sh" "$TMP/bin/"
  touch "$TMP/skills/lattice-lib/scripts/_lattice-home.sh"
  # Source must not list bare lattice-lib path candidates
  ! grep -E '["$]/lattice-lib/scripts' "$REPO_ROOT/skills/_lattice-lib/scripts/resolve-lattice-lib.sh"
  # Only legacy sibling present → fail; error mentions _lattice-lib / LATTICE_LIB_SCRIPTS
  run bash -c 'cd "$1" && unset LATTICE_LIB_SCRIPTS && bash "$2" --from "$3"' \
    _ "$TMP" "$TMP/bin/resolve-lattice-lib.sh" "$TMP/skills/start-work"
  [ "$status" -ne 0 ]
  [[ "$output" != *"/skills/lattice-lib/scripts"* ]]
  [[ "$output" == *"_lattice-lib"* ]] || [[ "$output" == *"LATTICE_LIB_SCRIPTS"* ]]
  # Env override still works
  run env LATTICE_LIB_SCRIPTS="$REPO_ROOT/skills/_lattice-lib/scripts" \
    bash "$REPO_ROOT/skills/_lattice-lib/scripts/resolve-lattice-lib.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/skills/_lattice-lib/scripts"* ]]
  rm -rf "$TMP"
}

@test "resolve-lattice-lib.sh resolves in a Codex-style flat install from its own trusted directory" {
  # Codex installs skills as flat siblings under e.g. ~/.agents/skills
  # with NO monorepo and NO git toplevel. The resolver's own directory is the
  # trust anchor; --from is accepted only for compatibility and is not searched.
  TMP=$(mktemp -d)
  mkdir -p "$TMP/skills/start-work" "$TMP/skills/_lattice-lib/scripts"
  cp "$REPO_ROOT/skills/_lattice-lib/scripts/resolve-lattice-lib.sh" "$TMP/skills/_lattice-lib/scripts/"
  touch "$TMP/skills/_lattice-lib/scripts/_lattice-home.sh"
  # Run from a non-git dir; call the resolver copy inside the flat install,
  # --from the calling skill dir, with no env override.
  run bash -c 'cd "$1" && unset LATTICE_LIB_SCRIPTS && bash "$2" --from "$3"' \
    _ "$TMP" "$TMP/skills/_lattice-lib/scripts/resolve-lattice-lib.sh" "$TMP/skills/start-work"
  [ "$status" -eq 0 ]
  # Must resolve to the flat-install lib, not the real monorepo path.
  [[ "$output" == "$TMP/skills/_lattice-lib/scripts" ]]
  [[ "$output" != *"$REPO_ROOT"* ]]
  [[ -f "$output/_lattice-home.sh" ]]
  rm -rf "$TMP"
}

@test "resolver ignores a caller-controlled --from scripts directory" {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/consumer/scripts"
  touch "$TMP/consumer/scripts/_lattice-home.sh"

  run bash "$REPO_ROOT/skills/_lattice-lib/scripts/resolve-lattice-lib.sh" --from "$TMP/consumer"
  [ "$status" -eq 0 ]
  [[ "$output" == "$REPO_ROOT/skills/_lattice-lib/scripts" ]]
  [[ "$output" != "$TMP/consumer/scripts" ]]
  rm -rf "$TMP"
}

@test "resolver rejects a relative LATTICE_LIB_SCRIPTS override" {
  run env LATTICE_LIB_SCRIPTS=skills/_lattice-lib/scripts \
    bash "$REPO_ROOT/skills/_lattice-lib/scripts/resolve-lattice-lib.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be an absolute"* ]]
}

@test "upload-github-asset lives under lattice-lib only" {
  [ -x "$LIB_UP" ]
  [ ! -e "$REPO_ROOT/skills/create-pr/scripts/upload-github-asset.sh" ]
  [ ! -e "$REPO_ROOT/skills/start-work/scripts/ensure-lattice.sh" ]
}
