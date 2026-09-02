#!/usr/bin/env bats
# Tests for after-pr-open.sh (spc-337 A3 / ADR-012 §1, tkt-339): the create-pr
# post-open step chains verify-main-chain.sh --stage pr THEN stamp-pr-open.sh.
# A FAILED proof exits non-zero and the stamp never runs; a verified proof
# stamps exactly once. _lattice-lib is swapped for a recording fake through the
# resolver's LATTICE_LIB_SCRIPTS override (no gh, no network).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export AFTER="$REPO_ROOT/skills/create-pr/scripts/after-pr-open.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/after-pr-open.XXXXXX")"
  MAIN="$TEST_DIR/repo"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email lattice-test@example.invalid
  git -C "$MAIN" config user.name 'Lattice Test'
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$MAIN" remote add origin git@github.com:acme/widgets.git

  # Fake _lattice-lib: resolver requires _lattice-home.sh to accept the dir.
  FAKE_LIB="$TEST_DIR/lib"
  mkdir -p "$FAKE_LIB"
  : >"$FAKE_LIB/_lattice-home.sh"
  export CALLS="$TEST_DIR/calls.log"
  : >"$CALLS"
  cat >"$FAKE_LIB/verify-main-chain.sh" <<'EOF'
#!/usr/bin/env bash
printf 'verify %s\n' "$*" >>"$CALLS"
if [[ "${VERIFY_FAIL:-}" == "true" ]]; then
  echo '{"stage":"pr","failed":"pr_probe_failed"}' >&2
  echo 'FAILED: pr proof — simulated (expected=abc actual=<absent>); cleanup/ledger HALTED' >&2
  exit 1
fi
echo "verified: pr-$4 repo=fake head_oid=$6"
EOF
  cat >"$FAKE_LIB/stamp-pr-open.sh" <<'EOF'
#!/usr/bin/env bash
printf 'stamp %s\n' "$*" >>"$CALLS"
if [[ "${STAMP_FAIL:-}" == "true" ]]; then echo "stamp boom" >&2; exit 1; fi
echo "stamp-pr-open: stamped pr-open"
EOF
  chmod +x "$FAKE_LIB"/*.sh
  export LATTICE_LIB_SCRIPTS="$FAKE_LIB"
  cd "$MAIN"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

@test "verified proof → stamp called exactly once with the PR + repo" {
  run bash "$AFTER" --pr 12 --expected-oid deadbeef --repo acme/widgets --expected-base dev
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verified: pr-12'
  printf '%s\n' "$output" | grep -qF 'after-pr-open: pr-12 verified + stamped'
  [ "$(grep -c '^verify ' "$CALLS")" -eq 1 ]
  [ "$(grep -c '^stamp ' "$CALLS")" -eq 1 ]
  grep -qF 'verify --stage pr --pr 12 --expected-oid deadbeef --repo acme/widgets --expected-base dev' "$CALLS"
  grep -qF 'stamp --pr 12 --repo acme/widgets' "$CALLS"
}

@test "FAILED proof → non-zero exit and stamp-pr-open is NOT run" {
  run env VERIFY_FAIL=true bash "$AFTER" --pr 12 --expected-oid deadbeef --repo acme/widgets
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED: pr proof'
  printf '%s\n' "$output" | grep -qF 'stamp-pr-open NOT run'
  [ "$(grep -c '^verify ' "$CALLS")" -eq 1 ]
  [ "$(grep -c '^stamp ' "$CALLS")" -eq 0 ]
}

@test "stamp failure after a verified proof exits 1 with a re-run hint" {
  run env STAMP_FAIL=true bash "$AFTER" --pr 12 --expected-oid deadbeef --repo acme/widgets
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'verified: pr-12'
  printf '%s\n' "$output" | grep -qF 'stamp-pr-open FAILED'
  printf '%s\n' "$output" | grep -qF -- '--pr 12 --repo acme/widgets'
}

@test "--repo defaults to origin owner/name" {
  run bash "$AFTER" --pr 7 --expected-oid deadbeef
  [ "$status" -eq 0 ]
  grep -qF 'verify --stage pr --pr 7 --expected-oid deadbeef --repo acme/widgets' "$CALLS"
  grep -qF 'stamp --pr 7 --repo acme/widgets' "$CALLS"
}

@test "--expected-head / --expected-body-file / --binder / --check-all pass through to the right helper" {
  printf 'body\n' >"$TEST_DIR/body.md"
  run bash "$AFTER" --pr 9 --expected-oid deadbeef --repo acme/widgets \
    --expected-head tkt-9-x --expected-body-file "$TEST_DIR/body.md" \
    --binder "$MAIN/.lattice/tickets/tkt-9-x/README.md" --check-all
  [ "$status" -eq 0 ]
  grep -qF -- "--expected-head tkt-9-x --expected-body-file $TEST_DIR/body.md" "$CALLS"
  grep -qF -- "stamp --pr 9 --repo acme/widgets --binder $MAIN/.lattice/tickets/tkt-9-x/README.md --check-all" "$CALLS"
  if grep '^verify ' "$CALLS" | grep -qF -- '--binder'; then false; fi
}

@test "usage errors: missing --pr / --expected-oid, non-numeric PR, unresolvable repo → exit 2, nothing called" {
  run bash "$AFTER" --expected-oid deadbeef
  [ "$status" -eq 2 ]
  run bash "$AFTER" --pr 3
  [ "$status" -eq 2 ]
  run bash "$AFTER" --pr https://github.com/acme/widgets/pull/3 --expected-oid deadbeef
  [ "$status" -eq 2 ]
  git remote remove origin
  run bash "$AFTER" --pr 3 --expected-oid deadbeef
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- '--repo <owner/name>'
  [ ! -s "$CALLS" ]
}

@test "missing helper in the resolved lib fails closed before verify" {
  rm -f "$FAKE_LIB/stamp-pr-open.sh"
  run bash "$AFTER" --pr 3 --expected-oid deadbeef --repo acme/widgets
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'stamp-pr-open.sh missing'
  [ ! -s "$CALLS" ]
}
