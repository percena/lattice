#!/usr/bin/env bats
# tkt-167: the bats assertion ergonomics guard.
#
# bash set -e never fires on failing `[[ ]]` (compound command) or `! cmd`
# (negation) outside a test body's last command, and `grep -q` inside a
# `[ -z "$( … )" ]` wrapper always expands empty. All three forms are banned;
# this suite proves the guard catches them and that the corpus stays clean.
#
# Assertion ergonomics: every assertion here is errexit-effective
# ([ ], grep -q, or terminal position).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export REPO_ROOT
  export CHECKER="$REPO_ROOT/tools/check-bats-assertions.py"
}

setup() {
  FIX="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIX"
}

@test "semantics proof: mid-body [[ ]] failure is masked, terminal one gates" {
  cat >"$FIX/semantics.bats" <<'EOF'
@test "masked mid-body" {
  x="actual"
  [[ "$x" == *"expected"* ]]
  true
}
@test "terminal [[ ]] gates" {
  x="actual"
  [[ "$x" == *"expected"* ]]
}
EOF
  run bats "$FIX/semantics.bats"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'ok 1 masked mid-body'
  printf '%s\n' "$output" | grep -qF 'not ok 2 terminal'
}

@test "guard flags all three banned forms in a planted fixture" {
  cat >"$FIX/planted.bats" <<'EOF'
@test "planted" {
  run true
  [[ "$output" == *"never checked"* ]]
  ! grep -q something /dev/null
  [ -z "$(printf '%s' "$output" | grep -qF also-always-true)" ]
}
EOF
  run python3 "$CHECKER" "$FIX/planted.bats"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'bare [[ ]] assertion'
  printf '%s\n' "$output" | grep -qF 'bare `! cmd` assertion'
  printf '%s\n' "$output" | grep -qF 'grep -q inside'
}

@test "guard passes the repo bats corpus" {
  run python3 "$CHECKER"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'files clean'
}

@test "guard ignores heredoc-embedded fixtures but still flags real violations" {
  cat >"$FIX/with-heredoc.bats" <<'EOF'
@test "embeds fixtures" {
  cat >"$T/inner.bats" <<'INNER'
@test "inner" {
  [[ "$output" == *"not a real assertion"* ]]
  ! grep -q nothing /dev/null
}
INNER
  run true
  [ "$status" -eq 0 ]
}
EOF
  # heredoc body must not be flagged → clean file passes
  run python3 "$CHECKER" "$FIX/with-heredoc.bats"
  [ "$status" -eq 0 ]
  # same file plus one REAL banned line outside the heredoc → flagged
  printf '  [[ "$output" == *"real violation"* ]]\n' >>"$FIX/with-heredoc.bats"
  run python3 "$CHECKER" "$FIX/with-heredoc.bats"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'bare [[ ]] assertion'
}
