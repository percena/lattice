#!/usr/bin/env bats
# Tests for detect-gh-pr-command.py (tkt-162).
#
# Assertion ergonomics: every test ends with a plain `[ "$status" -eq N ]`
# (errexit-effective). Deliberately no mid-body `[[ ]]` / `! cmd` assertions —
# bash set -e never fires on those, so they cannot gate a test (#167).

setup() {
  SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DETECT="$SCRIPTS_DIR/detect-gh-pr-command.py"
}

# detect <verb> <command> — pipe the command into the detector
detect() {
  printf '%s' "$2" | python3 "$DETECT" "$1"
}

# expect_detect <verb> <command> — the command IS a gh pr <verb> invocation
expect_detect() {
  run detect "$1" "$2"
  [ "$status" -eq 0 ]
}

# expect_safe <verb> <command> — NOT an invocation (exit 1); empty stdout
# also rules out a crash masquerading as "safe" (python exits 1 on an
# uncaught exception too, but then $output carries the traceback).
expect_safe() {
  run detect "$1" "$2"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# --- real invocations stay detected ------------------------------------------

@test "plain invocation detected" {
  expect_detect create 'gh pr create'
}

@test "wrapper invocation detected (sudo -u)" {
  expect_detect create 'sudo -u me gh pr create'
}

@test "unknown prefix stays fail-closed" {
  expect_detect create 'frobnicate gh pr create'
}

@test "xargs wrapper invocation detected" {
  expect_detect create 'xargs gh pr create </dev/null'
}

@test "find with -exec stays fail-closed" {
  expect_detect create 'find . -exec gh pr create {} +'
}

@test "find with -ok stays fail-closed" {
  expect_detect create 'find . -ok gh pr create \;'
}

@test "second region after && still detected when first region is a data command" {
  expect_detect create 'git status --short && gh pr create'
}

@test "merge verb detected" {
  expect_detect merge 'gh pr merge 42'
}

# --- data-argument commands are not invocations (tkt-162 false positives) ----

@test "touch with gh-shaped filenames is safe" {
  expect_safe create 'touch gh pr create'
}

@test "mv with gh-shaped filenames is safe" {
  expect_safe create 'mv gh pr create'
}

@test "git checkout with end-of-options and gh-shaped paths is safe" {
  expect_safe create 'git checkout -- gh pr create'
}

@test "git bisect run gh pr create is detected (bisect run executes its args)" {
  expect_detect create 'git bisect run gh pr create'
}

@test "git bisect run gh pr merge is detected for the merge verb" {
  expect_detect merge 'git bisect run gh pr merge 42'
}

@test "git bisect start with gh-shaped refs is safe (no run subcommand)" {
  expect_safe create 'git bisect start gh pr create'
}

@test "find search without exec flags is safe" {
  expect_safe create 'find . -name gh -o -name pr -o -name create'
}

@test "cat of gh-shaped filenames is safe" {
  expect_safe create 'cat gh pr create'
}

@test "echo stays safe (original safe list)" {
  expect_safe create 'echo gh pr create'
}

@test "sudo -u gh pr create runs 'pr' as user gh — not an invocation" {
  expect_safe create 'sudo -u gh pr create'
}

# --- verb/flag edges ----------------------------------------------------------

@test "create verb does not match merge" {
  expect_safe create 'gh pr merge 42'
}

@test "terminal flag --help is a docs lookup, not an attempt" {
  expect_safe create 'gh pr create --help'
}

@test "terminal flag before verb" {
  expect_safe create 'gh --help pr create'
}

@test "VALUE_FLAG consumes the next token (gh --repo pr create)" {
  expect_safe create 'gh --repo pr create'
}

@test "VALUE_FLAG missing its value" {
  expect_safe create 'gh --repo'
}

# --- accepted limitation: nested-shell payloads are invisible (pinned) --------
# The hook normalizer strips quoted strings before this detector runs; the
# payload is gone by design. Documented in the detector docstring.

@test "bash -c with quoted payload is not detected (accepted limitation)" {
  expect_safe create "bash -c 'gh pr create'"
}

@test "eval with quoted payload is not detected (accepted limitation)" {
  expect_safe create 'eval "gh pr create"'
}

@test "sh -c merge payload is not detected (accepted limitation)" {
  expect_safe merge 'sh -c "gh pr merge 1"'
}
