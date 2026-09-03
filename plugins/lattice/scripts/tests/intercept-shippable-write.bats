#!/usr/bin/env bats
# End-to-end tests for intercept-shippable-write.sh PreToolUse hook (L3).

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/intercept-shippable-write.sh"

  MAIN_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/main"
  git init -q "$MAIN_ROOT"
  git -C "$MAIN_ROOT" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN_ROOT" config user.email t@t.test
  git -C "$MAIN_ROOT" config user.name t
  git -C "$MAIN_ROOT" commit -q --allow-empty -m init
  mkdir -p "$MAIN_ROOT/.lattice/specs" "$MAIN_ROOT/.lattice/tickets" \
           "$MAIN_ROOT/.lattice/reviews" "$MAIN_ROOT/docs/adr" "$MAIN_ROOT/src"
  echo code >"$MAIN_ROOT/src/app.py"
  printf 'profile: strict\n' >"$MAIN_ROOT/.lattice/config.yaml"
  git -C "$MAIN_ROOT" add -A
  git -C "$MAIN_ROOT" commit -q -m files
  git -C "$MAIN_ROOT" worktree add -q "$MAIN_ROOT.wt" -b feat-wt
}

teardown() {
  git -C "$MAIN_ROOT" worktree remove --force "$MAIN_ROOT.wt" 2>/dev/null || true
  rm -rf "$MAIN_ROOT" "$MAIN_ROOT.wt" 2>/dev/null || true
}

# pipe a Write payload (cwd + file_path) into the hook
run_write() {  # <cwd> <file_path>
  local cwd="$1" path="$2"
  jq -cn --arg f "$path" --arg w "$cwd" \
    '{tool_name:"Write",tool_input:{file_path:$f},cwd:$w}' \
    | bash "$HOOK_SCRIPT" 2>&1
}

# ===================== main base: BLOCK =====================

@test "base: blocks .lattice/specs write" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/specs/spc-1.md"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "shippable write blocked"
}

@test "base: blocks .lattice/tickets write" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/tickets/tkt-1/R.md"
  [ "$status" -eq 2 ]
}

@test "base: blocks tracked product code write" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/src/app.py"
  [ "$status" -eq 2 ]
}

# ===================== exemptions: ALLOW on base =====================

@test "base: allows .lattice/reviews write (exempt)" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/reviews/rev-1.md"
  [ "$status" -eq 0 ]
}

@test "base: allows docs/adr write (exempt)" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/docs/adr/006-x.md"
  [ "$status" -eq 0 ]
}

# ===================== fail-open: ALLOW =====================

@test "allows new untracked file outside gated L0 (scratch)" {
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/src/new_untracked.py"
  [ "$status" -eq 0 ]
}

@test "allows write outside repo (/tmp)" {
  run run_write "$MAIN_ROOT" "${BATS_TEST_TMPDIR:-/tmp}/scratch.txt"
  [ "$status" -eq 0 ]
}

@test "allows non-Write/Edit tool (Read)" {
  run bash -c "jq -cn '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/etc/hosts\"}}' | '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
}

# ===================== worktree: ALLOW all =====================

@test "worktree: allows .lattice/specs write" {
  run run_write "$MAIN_ROOT.wt" "$MAIN_ROOT.wt/.lattice/specs/spc-3.md"
  [ "$status" -eq 0 ]
}

@test "worktree: allows tracked product code write" {
  run run_write "$MAIN_ROOT.wt" "$MAIN_ROOT.wt/src/app.py"
  [ "$status" -eq 0 ]
}

# ===================== non-base branch in main clone (strict): BLOCK =====================

@test "strict: blocks .lattice/specs write on non-base branch in main clone" {
  git -C "$MAIN_ROOT" checkout -q -b drift-branch
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/specs/spc-2.md"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF non_base_on_main_clone
}

# ===================== fail-open advisory (tkt-239) =====================

# Build a sanitized PATH that has the core tools + git + python3 but NOT jq,
# so `command -v jq` fails while the rest of the hook can still run.
make_path_without_jq() {
  local bin="$1"
  python3 - "$bin" <<'PY'
import os, shutil, sys
bin = sys.argv[1]
os.makedirs(bin, exist_ok=True)
for tool in ("cat","grep","sed","git","bash","dirname","basename","pwd",
            "test","find","head","tr","env","printf","cut","sort","uniq","wc",
            "rm","mkdir","touch","readlink","realpath","python3"):
    p = shutil.which(tool)
    if p:
        try: os.symlink(p, os.path.join(bin, tool))
        except FileExistsError: pass
PY
}

@test "fail-open: missing jq prints once-per-session advisory, exits 0 (tkt-239)" {
  local sid="dep-adv-$$-$RANDOM"
  local tdir="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  local bin="$tdir/bin"
  make_path_without_jq "$bin"
  # Build the Write payload WITHOUT jq (jq is the dep we simulate as missing).
  local pfile="$tdir/payload.json"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.lattice/specs/x.md"},"cwd":"%s","session_id":"%s"}' \
    "$MAIN_ROOT" "$MAIN_ROOT" "$sid" > "$pfile"
  run bash -c "TMPDIR='$tdir' PATH='$bin' '$HOOK_SCRIPT' < '$pfile' 2>&1"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "enforcement hook inert"
  printf '%s\n' "$output" | grep -qF "jq"
}

@test "fail-open: advisory is once-per-session (not repeated on second call)" {
  local sid="dep-adv-once-$$-$RANDOM"
  local tdir="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  local bin="$tdir/bin"
  make_path_without_jq "$bin"
  local pfile="$tdir/payload.json"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.lattice/specs/y.md"},"cwd":"%s","session_id":"%s"}' \
    "$MAIN_ROOT" "$MAIN_ROOT" "$sid" > "$pfile"
  run bash -c "TMPDIR='$tdir' PATH='$bin' '$HOOK_SCRIPT' < '$pfile' 2>&1"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "enforcement hook inert"
  # Second invocation with the SAME session_id -> sentinel exists -> silent.
  run bash -c "TMPDIR='$tdir' PATH='$bin' '$HOOK_SCRIPT' < '$pfile' 2>&1"
  [ "$status" -eq 0 ]
  if printf '%s\n' "$output" | grep -qF "enforcement hook inert"; then false; fi
}

# ===================== jq fail-open (tkt-326) =====================

@test "fail-open: empty assert output still prints remediation block (tkt-326)" {
  # Simulate assert-shippable-cwd.sh returning rc 1 with EMPTY stdout (e.g.
  # cwd worktree removed mid-session or assert internal error producing no
  # JSON). Before the fix, jq on empty input aborted under set -e before the
  # remediation block could print. After the fix, reason defaults to "unknown"
  # and the block still prints with exit 2.
  local fake_assert_dir="$MAIN_ROOT/skills/_lattice-lib/scripts"
  mkdir -p "$fake_assert_dir"
  cat >"$fake_assert_dir/assert-shippable-cwd.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$fake_assert_dir/assert-shippable-cwd.sh"
  # Set CLAUDE_PLUGIN_ROOT to a non-existent path so candidate 1 (plugin-tree
  # assert) is skipped; the fake assert at candidate 2 ($toplevel/skills/...)
  # is found instead.
  export CLAUDE_PLUGIN_ROOT=/nonexistent
  run run_write "$MAIN_ROOT" "$MAIN_ROOT/.lattice/specs/spc-1.md"
  unset CLAUDE_PLUGIN_ROOT
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "shippable write blocked"
  printf '%s\n' "$output" | grep -qF "unknown"
}
