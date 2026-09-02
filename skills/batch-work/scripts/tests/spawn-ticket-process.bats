#!/usr/bin/env bats
# Tests for spawn-ticket-process.sh: PID-liveness ground truth, the grace
# re-check that catches an immediate-crash spawn (tkt-242 L2), and the
# --dry-spawn / arg-guard surface. bats 1.13.0 — canonical `run` + `[ ]`.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export SPAWN="$REPO_ROOT/skills/batch-work/scripts/spawn-ticket-process.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spn.XXXXXX")"
  export TEST_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "self-test still passes with the grace re-check (regression guard)" {
  run bash "$SPAWN" --self-test
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "spawn-ticket-process.sh --self-test passed"
}

@test "immediate-crash spawn is detected via the grace re-check (tkt-242 L2)" {
  # Fake claude that sleeps briefly then exits 1 (simulates an auth/config/OOM
  # crash). It is alive at the first `kill -0` but dead after the grace wait,
  # so the spawn is reported as a failure, not recorded `running`.
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
sleep 0.05
exit 1
EOF
  chmod +x "$TEST_DIR/bin/claude"
  cwd="$TEST_DIR/wt"; mkdir -p "$cwd"
  brief="$TEST_DIR/brief"; printf 'dummy brief\n' >"$brief"
  run env PATH="$TEST_DIR/bin:$PATH" SPAWN_GRACE_SEC=0.2 \
    bash "$SPAWN" --cwd "$cwd" --brief-file "$brief"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "died immediately"
}

@test "missing claude binary: spawn fails closed (no live process)" {
  # tkt-353: a controlled PATH carries the shell utilities (bash/nohup/sleep
  # inherited from the host) plus a `claude` that cannot exec under ANY uid.
  # A non-executable file (chmod -x) can still exec under root on some
  # platforms, so the stub is a DIRECTORY — execve on a directory fails with
  # EACCES/EISDIR for every uid. The spawn subshell starts but claude cannot
  # exec; the grace re-check catches the dead PID.
  mkdir -p "$TEST_DIR/bin/claude"  # a directory named `claude` — never execable
  cwd="$TEST_DIR/wt"; mkdir -p "$cwd"
  brief="$TEST_DIR/brief"; printf 'dummy brief\n' >"$brief"
  run env PATH="$TEST_DIR/bin:$PATH" SPAWN_GRACE_SEC=0.2 \
    bash "$SPAWN" --cwd "$cwd" --brief-file "$brief"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qE "(did not produce a live process|died immediately)"
}

@test "--dry-spawn validates args and assembles the command without spawning" {
  cwd="$TEST_DIR/wt"; mkdir -p "$cwd"
  brief="$TEST_DIR/brief"; printf 'dummy brief\n' >"$brief"
  run bash "$SPAWN" --cwd "$cwd" --brief-file "$brief" --dry-spawn
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "dry-spawn: would run:"
  printf '%s\n' "$output" | grep -qF "state-file="
}

@test "missing --cwd and missing --brief-file fail closed (exit 2)" {
  brief="$TEST_DIR/brief"; printf 'x\n' >"$brief"
  run bash "$SPAWN" --brief-file "$brief"; [ "$status" -eq 2 ]
  cwd="$TEST_DIR/wt"; mkdir -p "$cwd"
  run bash "$SPAWN" --cwd "$cwd"; [ "$status" -eq 2 ]
}
