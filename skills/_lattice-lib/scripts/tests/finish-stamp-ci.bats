#!/usr/bin/env bats
# Tests for finish-stamp-ci.py — the GHA post-merge safety-net orchestrator
# (spc-416 A6 Layer 2). tkt-459 A1: the discovery and commit/push functions
# are exercised in-process (importlib) so no gh/network is required:
#   1. discover_binders matches `pr-N` on a word boundary (pr-44 ≠ pr-440)
#   2. commit_and_push commits the STAGED set only (unstaged edits survive)
#   3. push + fetch failure returns 1 (never a green run with an unstamped merge)
#   4. a failing --validator-script aborts the push (tkt-459 A4)

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export FSC="$REPO_ROOT/skills/_lattice-lib/scripts/finish-stamp-ci.py"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fsci.XXXXXX")"
  TICKETS="$TEST_DIR/.lattice/tickets"
  mkdir -p "$TICKETS"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# write_binder <dir-name> <prs-cell>
write_binder() {
  mkdir -p "$TICKETS/$1"
  cat >"$TICKETS/$1/README.md" <<MD
# $1

| Field | Value |
| --- | --- |
| status | pr-open |
| github | https://github.com/acme/repo/issues/${1#tkt-} |
| prs | $2 |
MD
}

# discover <pr-num> → prints the discovered binder dir names, one per line
discover() {
  python3 - "$FSC" "$TICKETS" "$1" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("fsc", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for b in m.discover_binders(sys.argv[2], int(sys.argv[3]), "", []):
    print(os.path.basename(os.path.dirname(b)))
PY
}

# Make a git repo with a bare origin; stage .lattice/b.md, leave .lattice/a.md
# modified-but-unstaged. Prints nothing; sets REPO + ORIGIN.
make_repo_with_origin() {
  REPO="$TEST_DIR/repo"; ORIGIN="$TEST_DIR/origin.git"
  git init -q --bare "$ORIGIN"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name T
  mkdir -p "$REPO/.lattice"
  printf 'a0\n' >"$REPO/.lattice/a.md"; printf 'b0\n' >"$REPO/.lattice/b.md"
  git -C "$REPO" add .lattice && git -C "$REPO" commit -qm base
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q origin main
  printf 'a1-unstaged\n' >"$REPO/.lattice/a.md"      # NOT staged
  printf 'b1-staged\n' >"$REPO/.lattice/b.md"; git -C "$REPO" add .lattice/b.md
}

# run_commit_and_push <validator-argv-json|null> → rc of commit_and_push
run_commit_and_push() {
  python3 - "$FSC" "$REPO" "$1" <<'PY'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("fsc", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
os.chdir(sys.argv[2])
validator = json.loads(sys.argv[3])
sys.exit(m.commit_and_push("main", 7, False, validator))
PY
}

@test "tkt-459 A1: discover_binders matches pr-N on a word boundary (pr-44 does not hit pr-440)" {
  write_binder tkt-44-alpha "pr-44 — https://github.com/acme/repo/pull/44"
  write_binder tkt-440-beta "pr-440 — https://github.com/acme/repo/pull/440"
  write_binder tkt-441-gamma "pr-4 — https://github.com/acme/repo/pull/4, pr-441 — https://github.com/acme/repo/pull/441"
  run discover 44
  [ "$status" -eq 0 ]
  [ "$output" = "tkt-44-alpha" ]
  run discover 440
  [ "$status" -eq 0 ]
  [ "$output" = "tkt-440-beta" ]
  run discover 4
  [ "$status" -eq 0 ]
  [ "$output" = "tkt-441-gamma" ]
}

@test "tkt-459 A1: commit_and_push commits the staged set only — unstaged .lattice edits are not swept in" {
  make_repo_with_origin
  run run_commit_and_push null
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "pushed safety-net stamp to main"
  # a.md is still modified-unstaged in the working tree
  run git -C "$REPO" status --porcelain -- .lattice/a.md
  [ "$output" = " M .lattice/a.md" ]
  # the commit that landed on origin carries b.md only
  run git -C "$REPO" show --stat --format= HEAD
  printf '%s\n' "$output" | grep -qF ".lattice/b.md"
  run bash -c "git -C '$REPO' show --stat --format= HEAD | grep -c 'a.md'"
  [ "$output" = "0" ]
  [ "$(git -C "$ORIGIN" rev-parse main)" = "$(git -C "$REPO" rev-parse HEAD)" ]
}

@test "tkt-459 A1: push failure + fetch failure returns 1 (not a silent green)" {
  make_repo_with_origin
  git -C "$REPO" remote set-url origin "$TEST_DIR/does-not-exist.git"
  run run_commit_and_push null
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "safety-net stamp NOT landed"
}

@test "tkt-459 A4: a failing --validator-script aborts the push (origin unchanged)" {
  make_repo_with_origin
  BEFORE="$(git -C "$ORIGIN" rev-parse main)"
  printf '#!/usr/bin/env python3\nimport sys; print("validator: FAIL"); sys.exit(1)\n' >"$TEST_DIR/bad-validator.py"
  run run_commit_and_push "[\"python3\", \"$TEST_DIR/bad-validator.py\"]"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "artifact validator FAILED"
  [ "$(git -C "$ORIGIN" rev-parse main)" = "$BEFORE" ]
}

@test "tkt-459 A4: a passing --validator-script still pushes" {
  make_repo_with_origin
  printf '#!/usr/bin/env python3\nprint("validator: OK")\n' >"$TEST_DIR/ok-validator.py"
  run run_commit_and_push "[\"python3\", \"$TEST_DIR/ok-validator.py\"]"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "validator: OK"
  [ "$(git -C "$ORIGIN" rev-parse main)" = "$(git -C "$REPO" rev-parse HEAD)" ]
}

@test "tkt-459 A1: --validator-script/--validator-baseline are accepted by the CLI (usage)" {
  run python3 "$FSC" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF -- "--validator-script"
  printf '%s\n' "$output" | grep -qF -- "--validator-baseline"
}
