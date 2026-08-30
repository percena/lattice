#!/usr/bin/env bats
# Tests for lattice-lib github-project-add.sh (stubbed gh; no network).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export ADD="$REPO_ROOT/skills/_lattice-lib/scripts/github-project-add.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gpa.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  cd "$MAIN"

  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export GH_MODE="ok"
  export GH_LOG="$TEST_DIR/gh.log"
  : >"$GH_LOG"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GH_LOG:-/dev/null}"
# `gh api user --jq .login` — emit the configured login (default empty = unresolved)
if [[ "${1:-}" == "api" && "${2:-}" == "user" ]]; then
  case "${GH_API_USER_MODE:-ok}" in
    fail) exit 1 ;;
    *) printf '%s' "${GH_USER_LOGIN:-}"; exit 0 ;;
  esac
fi
case "${GH_MODE:-ok}" in
  ok) exit 0 ;;
  already) echo "GraphQL: item already exists on project" >&2; exit 1 ;;
  scope) echo "Your token has not been granted the required scopes: project" >&2; exit 1 ;;
  fail) echo "boom" >&2; exit 1 ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"

  # Clean env that would enable the feature accidentally
  unset LATTICE_GITHUB_PROJECT_OWNER LATTICE_GITHUB_PROJECT_NUMBER
  unset LATTICE_GITHUB_PROJECT_ADD_ISSUES LATTICE_GITHUB_PROJECT_ADD_PRS
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "no config → silent no-op, never calls gh" {
  run bash "$ADD" "https://github.com/acme/r/issues/1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$GH_LOG" ]
}

@test "env owner+number → calls gh project item-add" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=12
  run bash "$ADD" "https://github.com/acme/r/issues/1"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "added to acme/projects/12"
  grep -F -e "project item-add 12 --owner acme --url https://github.com/acme/r/issues/1" "$GH_LOG"
}

@test ".env fills when env unset" {
  cat >"$MAIN/.env" <<'EOF'
# comment
LATTICE_GITHUB_PROJECT_OWNER=from-env-file
LATTICE_GITHUB_PROJECT_NUMBER=7
EOF
  run env LATTICE_GITHUB_PROJECT_ALLOW_DOTENV=1 bash "$ADD" "https://github.com/acme/r/issues/2"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "added to from-env-file/projects/7"
  grep -F -e "project item-add 7 --owner from-env-file" "$GH_LOG"
}

@test ".env.local overrides .env file values" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=base
LATTICE_GITHUB_PROJECT_NUMBER=1
EOF
  cat >"$MAIN/.env.local" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=local
LATTICE_GITHUB_PROJECT_NUMBER=99
EOF
  run env LATTICE_GITHUB_PROJECT_ALLOW_DOTENV=1 bash "$ADD" "https://github.com/acme/r/pull/3"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "added to local/projects/99"
}

@test ".env quoted value keeps ' # ' inside quotes; trailing comment after quote dropped" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER="acme # prod" # team board
LATTICE_GITHUB_PROJECT_NUMBER=7 # board number
EOF
  run env LATTICE_GITHUB_PROJECT_ALLOW_DOTENV=1 bash "$ADD" "https://github.com/acme/r/issues/2"
  [ "$status" -eq 0 ]
  grep -F -e "project item-add 7 --owner acme # prod --url" "$GH_LOG"
}

@test ".env unquoted value#fragment keeps the hash (no space before #)" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=acme#1
LATTICE_GITHUB_PROJECT_NUMBER=7
EOF
  run env LATTICE_GITHUB_PROJECT_ALLOW_DOTENV=1 bash "$ADD" "https://github.com/acme/r/issues/2"
  [ "$status" -eq 0 ]
  grep -F -e "project item-add 7 --owner acme#1" "$GH_LOG"
}

@test "process env wins over .env" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=file-owner
LATTICE_GITHUB_PROJECT_NUMBER=1
EOF
  export LATTICE_GITHUB_PROJECT_OWNER=env-owner
  export LATTICE_GITHUB_PROJECT_NUMBER=42
  run bash "$ADD" "https://github.com/acme/r/issues/4"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "added to env-owner/projects/42"
}

@test "ADD_ISSUES=false skips issues" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=12
  export LATTICE_GITHUB_PROJECT_ADD_ISSUES=false
  run bash "$ADD" "https://github.com/acme/r/issues/5"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ADD_ISSUES disabled"
  [ ! -s "$GH_LOG" ]
}

@test "ADD_PRS=false skips PRs" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=12
  export LATTICE_GITHUB_PROJECT_ADD_PRS=false
  run bash "$ADD" "https://github.com/acme/r/pull/6"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ADD_PRS disabled"
  [ ! -s "$GH_LOG" ]
}

@test "already on project → exit 0 soft success" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=12
  export GH_MODE=already
  run bash "$ADD" "https://github.com/acme/r/issues/7"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "already on acme/projects/12"
}

@test "missing project scope → exit 0 with hint" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=12
  export GH_MODE=scope
  run bash "$ADD" "https://github.com/acme/r/issues/8"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "gh missing project scope"
}

@test "generic gh failure → exit 0 non-fatal" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=12
  export GH_MODE=fail
  run bash "$ADD" "https://github.com/acme/r/issues/9"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "item-add failed (non-fatal)"
}

@test "non-digit project number → skip without gh" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=some-project
  run bash "$ADD" "https://github.com/acme/r/issues/10"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "must be digits"
  [ ! -s "$GH_LOG" ]
}

@test "non-github URL → skip without gh" {
  export LATTICE_GITHUB_PROJECT_OWNER=acme
  export LATTICE_GITHUB_PROJECT_NUMBER=12
  run bash "$ADD" "https://example.com/x"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "not a github.com URL"
  [ ! -s "$GH_LOG" ]
}

@test "no URL → skip exit 0" {
  run bash "$ADD"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "no URL"
}

@test "missing --url value → exit 0 (no hang)" {
  # Regression: shift 2 || true with only --url never advanced argv.
  run bash "$ADD" --url
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "requires a value"
  [ ! -s "$GH_LOG" ]
}

@test "script lives under lattice-lib only" {
  REPO_ROOT="$(cd "$(dirname "$ADD")/../../.." && pwd)"
  [ -x "$ADD" ]
  [ ! -e "$REPO_ROOT/skills/start-work/scripts/github-project-add.sh" ]
  [ ! -e "$REPO_ROOT/skills/create-pr/scripts/github-project-add.sh" ]
}

@test "a repository .env alone cannot authorize an external Project write" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=attacker-org
LATTICE_GITHUB_PROJECT_NUMBER=1
EOF
  GH_USER_LOGIN=alice run bash "$ADD" "https://github.com/acme/r/issues/2"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cannot authorize writing to an external board"
  # `gh api user` (a read) may be logged, but no `project item-add` write may occur.
  ! grep -q "item-add" "$GH_LOG"
}

@test "process env authorizes the write without the opt-in flag" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=attacker-org
LATTICE_GITHUB_PROJECT_NUMBER=1
EOF
  run env LATTICE_GITHUB_PROJECT_OWNER=trusted LATTICE_GITHUB_PROJECT_NUMBER=5 \
    bash "$ADD" "https://github.com/acme/r/issues/2"
  [ "$status" -eq 0 ]
  grep -F -e "project item-add 5 --owner trusted" "$GH_LOG"
  if grep -q "attacker-org" "$GH_LOG"; then false; fi
}

@test "self-owner .env auto-trusts without ALLOW_DOTENV (A1)" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=alice
LATTICE_GITHUB_PROJECT_NUMBER=7
EOF
  # No LATTICE_GITHUB_PROJECT_ALLOW_DOTENV set; OWNER == authenticated user.
  GH_USER_LOGIN=alice run bash "$ADD" "https://github.com/acme/r/issues/3"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "auto-trusted"
  printf '%s\n' "$output" | grep -qF "added to alice/projects/7"
  grep -F -e "project item-add 7 --owner alice" "$GH_LOG"
}

@test "self-owner auto-trust is case-insensitive (login casing)" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=Alice
LATTICE_GITHUB_PROJECT_NUMBER=7
EOF
  GH_USER_LOGIN=alice run bash "$ADD" "https://github.com/acme/r/issues/3"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "auto-trusted"
  grep -F -e "project item-add 7 --owner Alice" "$GH_LOG"
}

@test "non-self owner .env still gated (A2)" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=attacker-org
LATTICE_GITHUB_PROJECT_NUMBER=1
EOF
  # Authenticated user is alice; board owner is attacker-org → gate fires.
  GH_USER_LOGIN=alice run bash "$ADD" "https://github.com/acme/r/issues/3"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cannot authorize writing to an external board"
  # `gh api user` read may be logged, but no item-add write may occur.
  ! grep -q "item-add" "$GH_LOG"
}

@test "gh api user unavailable → gate retained, fail closed (A3)" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=alice
LATTICE_GITHUB_PROJECT_NUMBER=7
EOF
  # OWNER == alice, but gh api user fails (no auth / network) → cannot prove
  # self-ownership → fall back to the explicit opt-in, which is unset → skip.
  GH_API_USER_MODE=fail run bash "$ADD" "https://github.com/acme/r/issues/3"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cannot authorize writing to an external board"
  ! grep -q "item-add" "$GH_LOG"
}

@test "gh api user unresolved (empty login) → gate retained (A3 variant)" {
  cat >"$MAIN/.env" <<'EOF'
LATTICE_GITHUB_PROJECT_OWNER=alice
LATTICE_GITHUB_PROJECT_NUMBER=7
EOF
  # gh api user succeeds but returns an empty login (e.g. degraded response) →
  # do not auto-trust → gate fires.
  run bash "$ADD" "https://github.com/acme/r/issues/3"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "cannot authorize writing to an external board"
  ! grep -q "item-add" "$GH_LOG"
}
