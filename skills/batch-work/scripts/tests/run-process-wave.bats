#!/usr/bin/env bats
# Tests for run-process-wave.sh: the mktemp EXIT-trap (no state-file leak),
# the spawned-but-dead status that distinguishes an immediate-crash spawn
# from a silent `completed` (tkt-242 L2), and the spc-254 A1 false-success
# closure — process-node final state classified ok|failed|timeout|unknown
# from exit/result artifact + claude agents --json + PID + verify-mutation
# --expected-oid, with unknown fail-closing the binder to stuck + wait_reason:
# unblock via transition-api.py. bats 1.13.0 — canonical `run` + `[ ]`; the
# wave spawns detached `sleep` surrogates via fake helpers, never real claude.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export WAVE="$REPO_ROOT/skills/batch-work/scripts/run-process-wave.sh"
  export VERIFY="$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh"
  export TAPI="$REPO_ROOT/skills/_lattice-lib/scripts/transition-api.py"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wave.XXXXXX")"
  export TEST_DIR
  # Isolate the transition ledger so unknown fail-close writes never pollute
  # the repo's .lattice/ (spc-254 A1: unknown records a stuck ledger entry).
  LATTICE_HOME="$TEST_DIR/lattice-home"
  export LATTICE_HOME
  mkdir -p "$LATTICE_HOME"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# A fake spawn helper whose surrogates sleep long enough to be alive at the
# grace probe, then exit (settle within timebox). Mirrors the self-test helper
# shape; accepts --cwd/--brief-file/--state-file and --probe. Writes NO result
# artifact → the node classifies `unknown` (PID disappeared without exit/result).
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

# A fake helper that writes a result artifact to $BATCH_RESULT_FILE on behalf
# of its surrogate, then sleeps briefly and settles. Variant-driven by env:
#   FAKE_EXIT (default "0"), FAKE_PR, FAKE_OID — the result-artifact contents.
# When FAKE_EXIT=none, writes NO artifact (PID disappeared without a result).
build_result_helper() {
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
# Write the exit/result artifact the worker would have written (spc-254 A1).
if [[ -n "${BATCH_RESULT_FILE:-}" && "${FAKE_EXIT:-0}" != "none" ]]; then
  { printf 'exit=%s\n' "${FAKE_EXIT:-0}"
    [[ -n "${FAKE_PR:-}" ]] && printf 'pr=%s\n' "${FAKE_PR}"
    [[ -n "${FAKE_OID:-}" ]] && printf 'oid=%s\n' "${FAKE_OID}"
  } > "$BATCH_RESULT_FILE"
fi
# Surrogate sleeps past the grace probe (alive at grace → `running`) then
# settles at the barrier so classify_node runs (not spawned-but-dead).
( cd "$cwd" && exec nohup sleep 1 >/dev/null 2>&1 ) &
pid=$!; disown "$pid" 2>/dev/null || true
echo "spawned: pid=$pid worktree=$cwd"
echo "state-file=$state"
EOF
  chmod +x "$f"
}

# A fake verify-mutation that exits 0 (verified) for the asserted PR/oid and
# 1 (FAILED) otherwise — stands in for the real helper in the ok-path test.
build_fake_verify() {
  local f="$1" pr="$2" oid="$3"
  cat >"$f" <<EOF
#!/usr/bin/env bash
# fake verify-mutation: verifies pr=$pr oid=$oid
for a in "\$@"; do :; done
if [[ "\$*" == *"--pr $pr"* && "\$*" == *"--expected-oid $oid"* ]]; then
  echo "verified: fake pr-$pr head=$oid"
  exit 0
fi
echo "FAILED: fake verify-mutation mismatch (\$*)" >&2
exit 1
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
    --spawn-helper "$fast_helper" --verify-helper "$VERIFY" \
    --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  # --state-file was passed, so no auto-mktemp; results dir is auto-mktemp'd
  # but the EXIT trap cleans it → nothing observable in the isolated dir.
  [ "$(count_leftover "$ISO_TMP")" -eq 0 ]
}

@test "wave with NO --state-file auto-mktemps and cleans it on exit (tkt-242 L2)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-A\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  ISO_TMP="$TEST_DIR/tmp"; mkdir -p "$ISO_TMP"
  # No --state-file → the wave mktemps one + a results dir; the EXIT trap
  # must remove both.
  run env TMPDIR="$ISO_TMP" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$fast_helper" --verify-helper "$VERIFY" \
    --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1
  [ "$status" -eq 0 ]
  [ "$(count_leftover "$ISO_TMP")" -eq 0 ]
}

@test "immediate-crash spawn is reported spawned-but-dead, not ok (tkt-242 L2)" {
  dying_helper="$TEST_DIR/dying.sh"
  build_dying_helper "$dying_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-A\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env SPAWN_GRACE_SEC=0.2 bash "$WAVE" --manifest "$m" \
    --spawn-helper "$dying_helper" --verify-helper "$VERIFY" \
    --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "spawned-but-dead"
  printf '%s\n' "$output" | grep -qF "spawned-but-dead: 1"
  # NOT reported as ok (spc-254 A1: a PID that disappeared is never success).
  printf '%s\n' "$output" | grep -qF "ok: 0"
}

@test "missing worktree → workspace-failed (not a hard crash)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; brief="$TEST_DIR/brief"; printf 'x\n' >"$brief"
  printf 'tkt-X\t/nonexistent/wt\t%s\t1\n' "$brief" >"$m"
  run env bash "$WAVE" --manifest "$m" --spawn-helper "$fast_helper" \
    --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "workspace-failed: 1"
}

@test "missing --manifest fails closed (exit 2)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  run bash "$WAVE" --spawn-helper "$fast_helper" --verify-helper "$VERIFY"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# spc-254 A1 — false-success closure (fault injection)
# ---------------------------------------------------------------------------

@test "A1: worker exits non-zero → failed (never completed/ok)" {
  # A worker that runs, then fails (exit 1) and records exit=1 in its result
  # artifact is classified `failed`, NOT `ok`/`completed`. This is the core
  # false-success closure: a PID that disappeared after a crash is never
  # success.
  helper="$TEST_DIR/exit1.sh"
  FAKE_EXIT=1 build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-F\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env FAKE_EXIT=1 bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "failed: 1"
  printf '%s\n' "$output" | grep -qF "ok: 0"
  printf '%s\n' "$output" | grep -qF "unknown: 0"
}

@test "A1: PID disappears without an opened PR → unknown (never completed/ok)" {
  # A worker whose PID disappears leaving NO result artifact (no exit code, no
  # PR claim) is classified `unknown` — fail-closed, never `ok`/`completed`.
  # The wave records the binder in-progress → stuck flip via transition-api.py.
  helper="$TEST_DIR/nopr.sh"
  FAKE_EXIT=none build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-U\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env FAKE_EXIT=none bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "unknown: 1"
  printf '%s\n' "$output" | grep -qF "ok: 0"
  printf '%s\n' "$output" | grep -qF "failed: 0"
}

@test "A1: unknown fail-closes binder to stuck + wait_reason: unblock (transition ledger)" {
  # The unknown classification records a transition ledger entry
  # in-progress → stuck with trace "wait_reason: unblock" via transition-api.py
  # (tkt-255). The validator replays this edge; it is legal per the schema.
  helper="$TEST_DIR/nopr.sh"
  FAKE_EXIT=none build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-U\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env FAKE_EXIT=none bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  ledger="$LATTICE_HOME/.transition-ledger/tkt-U.jsonl"
  [ -f "$ledger" ]
  grep -qF '"from":"in-progress"' "$ledger"
  grep -qF '"to":"stuck"' "$ledger"
  grep -qF '"trace":"wait_reason: unblock"' "$ledger"
}

@test "A1: ok requires exit=0 + verify-mutation --expected-oid agreement" {
  # A worker that exits 0, claims a PR+oid, and whose claim verify-mutation
  # confirms → `ok`. Demonstrates the agreement requirement: all available
  # signals agree (exit/result artifact + verify-mutation; agents --json
  # enrichment is unavailable in tests and does not veto).
  helper="$TEST_DIR/ok.sh"
  FAKE_EXIT=0 FAKE_PR=42 FAKE_OID=abc1234 build_result_helper "$helper"
  fake_verify="$TEST_DIR/vm.sh"
  build_fake_verify "$fake_verify" 42 abc1234
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-O\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env FAKE_EXIT=0 FAKE_PR=42 FAKE_OID=abc1234 bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$fake_verify" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok: 1"
  printf '%s\n' "$output" | grep -qF "unknown: 0"
  printf '%s\n' "$output" | grep -qF "failed: 0"
}

@test "A1: phantom PR (verify-mutation FAILED) → failed (not ok)" {
  # A worker that claims a PR but verify-mutation cannot confirm it → `failed`
  # (phantom PR). This is the rev-20260829-140444Z F5 false-success incident
  # closed in-wave: the claim is not trusted on the worker's word alone.
  helper="$TEST_DIR/phantom.sh"
  FAKE_EXIT=0 FAKE_PR=99 FAKE_OID=deadbeef build_result_helper "$helper"
  fake_verify="$TEST_DIR/vm.sh"
  # fake verify rejects any oid other than the one it expects (abc1234)
  build_fake_verify "$fake_verify" 42 abc1234
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-P\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env FAKE_EXIT=0 FAKE_PR=99 FAKE_OID=deadbeef bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$fake_verify" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "failed: 1"
  printf '%s\n' "$output" | grep -qF "ok: 0"
}
