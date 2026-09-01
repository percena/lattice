#!/usr/bin/env bats
# verify-main-chain.bats — mutation-proof the create-pr → merge chain (spc-254 A2/D5).
# Fault-injection: each stage's mismatch/absence halts (exit 1) and emits the
# structured recovery JSON. Normal success verifies (exit 0).
# tkt-167 ergonomics: run + [ "$status" ... ]; [ ! -f ] / [ -f ]. No bare !/[[ ]].

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
export REPO_ROOT
SCRIPT="$REPO_ROOT/skills/_lattice-lib/scripts/verify-main-chain.sh"
VERIFY_MUTATION="$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh"

# Shared fake binaries: gh + git (ls-remote). Tests override per-case.
setup_bin() {
  local dir="$1"
  mkdir -p "$dir/bin"
  printf '#!/usr/bin/env bash\n' > "$dir/bin/gh"
  printf '#!/usr/bin/env bash\n' > "$dir/bin/git"
  chmod +x "$dir/bin/gh" "$dir/bin/git"
}

write_fake_gh_pr() {
  # $1 = dir, $2 = state, $3 = headRefOid, $4 = url, $5 = baseRefName, $6 = headRefName, $7 = body
  # $8 (optional) = merge_commit_sha for `gh api repos/.../pulls/N` (merge stage).
  local dir="$1" state="$2" head="$3" url="$4" base="$5" headname="$6" body="$7"
  local mcs="${8:-}"
  local json_line
  json_line=$(BODY="$body" STATE="$state" HEAD="$head" URL="$url" BASE="$base" HEADNAME="$headname" \
    python3 -c 'import json,os; print(json.dumps({"state":os.environ["STATE"],"headRefOid":os.environ["HEAD"],"url":os.environ["URL"],"baseRefName":os.environ["BASE"],"headRefName":os.environ["HEADNAME"],"body":os.environ["BODY"]}))')
  printf '%s\n' "$json_line" > "$dir/gh.response"
  local api_json=""
  if [ -n "$mcs" ]; then
    api_json=$(MCS="$mcs" HEAD="$head" python3 -c 'import json,os; print(json.dumps({"merge_commit_sha":os.environ["MCS"],"headRefOid":os.environ["HEAD"]}))')
  fi
  printf '%s\n' "$api_json" > "$dir/gh.api.response"
  cat > "$dir/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr view") cat "$dir/gh.response" ;;
  api*) cat "$dir/gh.api.response" ;;   # full PR JSON; script extracts fields
  *) exit 1 ;;
esac
EOF
  chmod +x "$dir/bin/gh"
}

teardown() {
  [ -n "${FAKE_DIR:-}" ] && rm -rf "$FAKE_DIR" 2>/dev/null || true
  rm -f "$REPO_ROOT/.vm.err" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# stage push
# ---------------------------------------------------------------------------

@test "push: usage no args exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "push: remote OID matches local HEAD verifies (exit 0)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-push-ok-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  FULL=$(git -C "$REPO_ROOT" rev-parse HEAD)
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls-remote) printf '%s\trefs/heads/%s\n' "$FULL" "\$3" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage push --branch feat-x --expected-oid "$FULL"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verified: push branch=feat-x'
}

@test "push: remote OID mismatch halts with recovery JSON (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-push-bad-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls-remote) printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\trefs/heads/%s\n' "\$3" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage push --branch feat-x --expected-oid abc1234abc1234
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED: push proof'
  # structured recovery JSON on stderr (captured into $output by bats run)
  printf '%s\n' "$output" | grep -qF '"stage":"push"'
  printf '%s\n' "$output" | grep -qF '"failed":"remote_oid_mismatch"'
  printf '%s\n' "$output" | grep -qF '"next_action"'
}

@test "push: absent remote branch halts (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-push-absent-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  cat > "$FAKE_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls-remote) : ;;  # empty output = absent ref
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage push --branch ghost --expected-oid abc1234abc1234
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED: push proof'
}

# ---------------------------------------------------------------------------
# stage pr
# ---------------------------------------------------------------------------

@test "pr: existing OPEN PR at expected head verifies (exit 0)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-pr-ok-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body-text"
  printf 'body-text' > "$FAKE_DIR/body.md"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage pr --pr 1 \
    --expected-oid abc1234abcd --repo percena/lattice \
    --expected-base dev --expected-head feat-x --expected-body-file "$FAKE_DIR/body.md"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verified: pr-1'
}

@test "pr: head OID mismatch halts with recovery JSON (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-pr-oid-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage pr --pr 1 --expected-oid deadbeef --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED: pr proof'
  printf '%s\n' "$output" | grep -qF '"stage":"pr"'
  printf '%s\n' "$output" | grep -qF '"next_action"'
}

@test "pr: wrong repo halts (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-pr-repo-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "OPEN" "abc1234abcd" "https://github.com/other/repo/pull/1" "dev" "feat-x" "body"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage pr --pr 1 --expected-oid abc1234abcd --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED: pr proof'
}

@test "pr: base mismatch halts with recovery JSON (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-pr-base-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "main" "feat-x" "body"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage pr --pr 1 \
    --expected-oid abc1234abcd --repo percena/lattice --expected-base dev
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED: pr proof'
  printf '%s\n' "$output" | grep -qF '"failed":"base_mismatch"'
  printf '%s\n' "$output" | grep -qF 'gh pr edit'
}

@test "pr: head branch mismatch halts (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-pr-head-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "wrong-branch" "body"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage pr --pr 1 \
    --expected-oid abc1234abcd --repo percena/lattice --expected-head feat-x
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"head_branch_mismatch"'
}

@test "pr: body mismatch halts (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-pr-body-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "actual-body"
  printf 'expected-body' > "$FAKE_DIR/body.md"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage pr --pr 1 \
    --expected-oid abc1234abcd --repo percena/lattice --expected-body-file "$FAKE_DIR/body.md"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"body_mismatch"'
}

@test "pr: missing --repo exits 2 (repo identity binding required)" {
  run bash "$SCRIPT" --stage pr --pr 1 --expected-oid abc1234abcd
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# stage merge
# ---------------------------------------------------------------------------

@test "merge: MERGED + base advanced + ancestry proven verifies (A4.3, exit 0)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-ok-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  MCS="2222222222222222222222222222222222222222"
  write_fake_gh_pr "$FAKE_DIR" "MERGED" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body" "$MCS"
  PRE="0000000000000000000000000000000000000000"
  POST="1111111111111111111111111111111111111111"
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls-remote) printf '%s\trefs/heads/dev\n' "$POST" ;;
  # git fetch origin <base_ref SHA> — succeed (merge commit now in object DB)
  fetch) exit 0 ;;
  # git merge-base --is-ancestor <mcs> <base_ref> → ancestor → exit 0
  merge-base) exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid "$PRE" --repo percena/lattice
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verified: merge pr-1'
  printf '%s\n' "$output" | grep -qF 'state=MERGED'
  printf '%s\n' "$output" | grep -qF 'ancestry proven'
}

@test "merge: PR not MERGED halts with recovery JSON (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-state-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "OPEN" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body"
  cat > "$FAKE_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls-remote) printf '1111111111111111111111111111111111111111\trefs/heads/dev\n' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid 0000000000000000000000000000000000000000 --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'FAILED: merge proof'
  printf '%s\n' "$output" | grep -qF '"stage":"merge"'
  printf '%s\n' "$output" | grep -qF '"failed":"merged_state_failed"'
  printf '%s\n' "$output" | grep -qF '"next_action"'
}

@test "merge: base tip did not advance halts (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-noadvance-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  PRE="0000000000000000000000000000000000000000"
  write_fake_gh_pr "$FAKE_DIR" "MERGED" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body"
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls-remote) printf '%s\trefs/heads/dev\n' "$PRE" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid "$PRE" --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"base_tip_not_advanced"'
  printf '%s\n' "$output" | grep -qF 'do NOT run finish-ledger/cleanup'
}

@test "merge: base tip absent halts (fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-absent-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "MERGED" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body"
  cat > "$FAKE_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls-remote) : ;;  # absent ref
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid 0000000000000000000000000000000000000000 --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"base_tip_absent"'
}

@test "merge: merge_commit_sha not ancestor of base halts (A4.4 concurrent unrelated advancement, fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-noanc-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  MCS="3333333333333333333333333333333333333333"
  write_fake_gh_pr "$FAKE_DIR" "MERGED" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body" "$MCS"
  PRE="0000000000000000000000000000000000000000"
  POST="1111111111111111111111111111111111111111"
  # fake git: base advanced (POST≠PRE) BUT merge-base says MCS is NOT an ancestor
  # of the live base tip (concurrent unrelated PR advanced the base).
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls-remote) printf '%s\trefs/heads/dev\n' "$POST" ;;
  fetch) exit 0 ;;
  merge-base) exit 1 ;;   # NOT an ancestor of base_ref → ancestry proof fails
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid "$PRE" --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"merge_commit_not_ancestor"'
  printf '%s\n' "$output" | grep -qF 'do NOT run finish-ledger/cleanup'
}

@test "merge: no merge_commit_sha halts (A4.3 unresolved, fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-nomcs-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "MERGED" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body" "null"
  PRE="0000000000000000000000000000000000000000"
  POST="1111111111111111111111111111111111111111"
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls-remote) printf '%s\trefs/heads/dev\n' "$POST" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid "$PRE" --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"merge_commit_unresolved"'
}

@test "merge: gh api failure halts with transient hint (A4.3 api_failed, fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-apifail-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  write_fake_gh_pr "$FAKE_DIR" "MERGED" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body"
  # fake gh: api exits 1 (transient 5xx/rate-limit); pr view still works
  printf '%s\n' '{}' > "$FAKE_DIR/gh.api.response"
  cat > "$FAKE_DIR/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr view") cat "$FAKE_DIR/gh.response" ;;
  api*) exit 1 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/gh"
  PRE="0000000000000000000000000000000000000000"
  POST="1111111111111111111111111111111111111111"
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in ls-remote) printf '%s\trefs/heads/dev\n' "$POST" ;; *) exit 0 ;; esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid "$PRE" --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"merge_commit_api_failed"'
  printf '%s\n' "$output" | grep -qF 'transient'
}

@test "merge: git fetch of base tip fails halts (A4.3 base_fetch_failed, fault-injection)" {
  FAKE_DIR="$BATS_TMPDIR/vmc-merge-fetchfail-${BATS_TEST_NUMBER}-$$"
  setup_bin "$FAKE_DIR"
  MCS="2222222222222222222222222222222222222222"
  write_fake_gh_pr "$FAKE_DIR" "MERGED" "abc1234abcd" "https://github.com/percena/lattice/pull/1" "dev" "feat-x" "body" "$MCS"
  PRE="0000000000000000000000000000000000000000"
  POST="1111111111111111111111111111111111111111"
  cat > "$FAKE_DIR/bin/git" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls-remote) printf '%s\trefs/heads/dev\n' "$POST" ;;
  fetch) exit 1 ;;   # fetch of base_ref fails (network/auth) → fail closed
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_DIR/bin/git"
  run env PATH="$FAKE_DIR/bin:$PATH" bash "$SCRIPT" --stage merge --pr 1 \
    --expected-oid "$PRE" --repo percena/lattice
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '"failed":"base_fetch_failed"'
}

@test "merge: --pr required (exit 2)" {
  run bash "$SCRIPT" --stage merge --expected-oid 0000000
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# shared contract / unknown stage
# ---------------------------------------------------------------------------

@test "unknown stage exits 2" {
  run bash "$SCRIPT" --stage bogus --pr 1 --expected-oid abc1234
  [ "$status" -eq 2 ]
}

@test "verify-mutation.sh foundation still probes --expected-oid (tkt-255 not regressed)" {
  # The main-chain helper delegates remote/PR/merge-state probes to the
  # tkt-255 foundation. Confirm it still honors --expected-oid (no regression
  # from the wiring). Smoke-test the shared contract surface.
  [ -f "$VERIFY_MUTATION" ]
  run bash "$VERIFY_MUTATION" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF -- '--expected-oid'
}
