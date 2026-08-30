#!/usr/bin/env bats
# Tests for run-process-wave.sh: the mktemp EXIT-trap (no state-file leak)
# and the spawned-but-dead status that distinguishes an immediate-crash
# spawn from a silent `completed` (tkt-242 L2). bats 1.13.0 — canonical
# `run` + `[ ]`; the wave spawns detached `sleep` surrogates via a fake
# helper, never real claude.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export WAVE="$REPO_ROOT/skills/batch-work/scripts/run-process-wave.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wave.XXXXXX")"
  export TEST_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}

# A fake spawn helper whose surrogates sleep long enough to be alive at the
# grace probe, then exit (completed within timebox). Mirrors the self-test
# helper shape; accepts --cwd/--brief-file/--state-file and --probe.
build_fast_helper() {
  local f="$1"
  cat >"$f" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--probe" ]]; then
  pid="$2"; [[ "$pid" =~ ^[0-9]+$ ]] || { echo "dead: $pid"; exit 0; }
  if kill -0 "$pid" 2>/dev/null; then echo "alive: $pid"; else echo "dead: $pid"; fi
  exit 0
fi
cwd=""; brief=""; state=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) cwd="$2"; shift 2 ;;
    --brief-file) brief="$2"; shift 2 ;;
    --state-file) state="$2"; shift 2 ;;
    *) shift ;;
  esac
done
( cd "$cwd" && exec nohup sleep 1 >/dev/null 2>&1 ) &
pid=$!; disown "$pid" 2>/dev/null || true
echo "spawned: pid=$pid worktree=$cwd"
echo "state-file=$state"
EOF
  chmod +x "$f"
}

# A fake helper whose surrogate sleeps briefly then exits 1 (claude-crash).
build_dying_helper() {
  local f="$1"
  cat >"$f" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--probe" ]]; then
  pid="$2"; [[ "$pid" =~ ^[0-9]+$ ]] || { echo "dead: $pid"; exit 0; }
  if kill -0 "$pid" 2>/dev/null; then echo "alive: $pid"; else echo "dead: $pid"; fi
  exit 0
fi
cwd=""; brief=""; state=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) cwd="$2"; shift 2 ;;
    --brief-file) brief="$2"; shift 2 ;;
    --state-file) state="$2"; shift 2 ;;
    *) shift ;;
  esac
done
( cd "$cwd" && exec nohup bash -c 'sleep 0.05; exit 1' >/dev/null 2>&1 ) &
pid=$!; disown "$pid" 2>/dev/null || true
echo "spawned: pid=$pid worktree=$cwd"
echo "state-file=$state"
EOF
  chmod +x "$f"
}

# Count files left in an isolated TMPDIR (no pipes — glob + test, env-safe).
count_leftover() {
  local d="$1" n=0 f
  for f in "$d"/*; do [ -e "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

@test "auto-created state file is cleaned on wave exit (no leak) (tkt-242 L2)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-A\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  # Isolate mktemp so the wave's auto-created state file is observable.
  ISO_TMP="$TEST_DIR/tmp"; mkdir -p "$ISO_TMP"
  run env TMPDIR="$ISO_TMP" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$fast_helper" --ram-threshold 0 \
    --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  # --state-file was passed, so no auto-mktemp; nothing in the isolated dir.
  [ "$(count_leftover "$ISO_TMP")" -eq 0 ]
}

@test "wave with NO --state-file auto-mktemps and cleans it on exit (tkt-242 L2)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-A\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  ISO_TMP="$TEST_DIR/tmp"; mkdir -p "$ISO_TMP"
  # No --state-file → the wave mktemps one and the EXIT trap must remove it.
  run env TMPDIR="$ISO_TMP" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$fast_helper" --ram-threshold 0 \
    --poll-interval 1 --concurrency 1
  [ "$status" -eq 0 ]
  [ "$(count_leftover "$ISO_TMP")" -eq 0 ]
}

@test "immediate-crash spawn is reported spawned-but-dead, not completed (tkt-242 L2)" {
  dying_helper="$TEST_DIR/dying.sh"
  build_dying_helper "$dying_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-A\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env SPAWN_GRACE_SEC=0.2 bash "$WAVE" --manifest "$m" \
    --spawn-helper "$dying_helper" --ram-threshold 0 \
    --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "spawned-but-dead"
  printf '%s\n' "$output" | grep -qF "spawned-but-dead: 1"
  # NOT reported as completed
  printf '%s\n' "$output" | grep -qF "completed: 0"
}

@test "missing worktree → workspace-failed (not a hard crash)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; brief="$TEST_DIR/brief"; printf 'x\n' >"$brief"
  printf 'tkt-X\t/nonexistent/wt\t%s\t1\n' "$brief" >"$m"
  run env bash "$WAVE" --manifest "$m" --spawn-helper "$fast_helper" \
    --ram-threshold 0 --poll-interval 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "workspace-failed: 1"
}

@test "missing --manifest fails closed (exit 2)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  run bash "$WAVE" --spawn-helper "$fast_helper"
  [ "$status" -eq 2 ]
}
