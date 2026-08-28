#!/usr/bin/env bats
# Unit tests for detect-git-branch-op.py — the pure-parse classifier.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DETECTOR="$SCRIPT_DIR/detect-git-branch-op.py"
}

# feed a command, print detector JSON
detect() {
  printf '%s' "$1" | python3 "$DETECTOR" 2>/dev/null
}

assert_op() {  # <command> <expected-op> [expected-target]
  local cmd="$1" exp_op="$2" exp_target="${3:-}"
  local res op target
  res=$(detect "$cmd")
  op=$(printf '%s' "$res" | jq -r '.op')
  target=$(printf '%s' "$res" | jq -r '.target // ""')
  [ "$op" = "$exp_op" ]
  if [[ -n "$exp_target" ]]; then
    [ "$target" = "$exp_target" ]
  fi
}

# ---------------- create ----------------

@test "checkout -b is create" {
  assert_op 'git checkout -b tmp-fix' create tmp-fix
}

@test "bound name create is still create (drift path)" {
  assert_op 'git checkout -b tkt-8-foo' create tkt-8-foo
}

@test "checkout -B is create" {
  assert_op 'git checkout -B feat/x-y' create 'feat/x-y'
}

@test "switch -c is create" {
  assert_op 'git switch -c tmp' create tmp
}

@test "switch -C is create" {
  assert_op 'git switch -C tmp' create tmp
}

@test "git branch <name> is create" {
  assert_op 'git branch tmp' create tmp
}

# ---------------- none (not a branch create/switch) ----------------

@test "git status is none" {
  assert_op 'git status' none
}

@test "git pull is none" {
  assert_op 'git pull' none
}

@test "git branch -a (list) is none" {
  assert_op 'git branch -a' none
}

@test "git branch -d (delete) is none" {
  assert_op 'git branch -d tmp' none
}

@test "git checkout -- file (file restore) is none" {
  assert_op 'git checkout -- file.txt' none
}

@test "ensure-workspace invocation is none (blessed entry, not raw git)" {
  assert_op 'bash /x/ensure-workspace.sh --mode worktree --bind tkt --id 8 --slug foo' none
}

@test "echo git checkout -b foo is none (git is an argument, not invocation)" {
  assert_op 'echo git checkout -b foo' none
}

@test "git switch --detach is none" {
  assert_op 'git switch --detach' none
}

# ---------------- switch (existing branch) ----------------

@test "git switch <name> is switch" {
  assert_op 'git switch dev' switch dev
}

@test "git checkout <name> (no -b) is switch" {
  assert_op 'git checkout somefile.txt' switch somefile.txt
}

# ---------------- compound / wrappers ----------------

@test "drift hidden after cd is detected (cd /x && git checkout -b foo)" {
  assert_op 'cd /tmp && git checkout -b foo' create foo
}

@test "git -C <path> override is captured" {
  local res cwd_ov
  res=$(detect 'git -C /tmp/x checkout -b foo')
  cwd_ov=$(printf '%s' "$res" | jq -r '.cwd_override')
  [ "$cwd_ov" = "/tmp/x" ]
}

@test "sudo git checkout -b foo is create" {
  assert_op 'sudo git checkout -b foo' create foo
}
