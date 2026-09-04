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
  # ADR-011 / spc-282 A2: coordinator + ledger .lock relocate to the out-of-repo
  # state home (fingerprint-resolved, not --lattice-home). Pin it to the test
  # temp so the --coordinator wiring test finds state where it expects.
  LATTICE_STATE_HOME="$LATTICE_HOME"
  export LATTICE_STATE_HOME
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
( cd "$cwd" && exec nohup sleep 4 >/dev/null 2>&1 ) &
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
  # tkt-463: `if`, not `[[ ]] &&` — under bash 3.2 (macOS) a failing && list
  # as the group's last command trips `set -e` and the helper dies before
  # spawning its surrogate.
  { printf 'exit=%s\n' "${FAKE_EXIT:-0}"
    if [[ -n "${FAKE_PR:-}" ]]; then printf 'pr=%s\n' "${FAKE_PR}"; fi
    if [[ -n "${FAKE_OID:-}" ]]; then printf 'oid=%s\n' "${FAKE_OID}"; fi
  } > "$BATCH_RESULT_FILE"
fi
# Surrogate sleeps past the grace probe (alive at grace → `running`) then
# settles at the barrier so classify_node runs (not spawned-but-dead).
# tkt-463: 4s, not 1s — the wave runs several python3 startups (coordinator
# record-spawn, transition-api) BEFORE its 0.3s grace probe; on GitHub runners
# that exceeded 1s, the surrogate was already dead and every A1/A2/A6 test
# collapsed to spawned-but-dead (both ubuntu and macOS, PR #466).
( cd "$cwd" && exec nohup sleep 4 >/dev/null 2>&1 ) &
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

# Create a minimal binder under LATTICE_HOME for <ticket> so the atomic
# transition-api commit (spc-270 A2.2) can flip | status | in one transaction.
# <status> defaults to in-progress (the legal pre-stuck from-state).
build_binder() {
  local ticket="$1" status="${2:-in-progress}"
  local bdir="$LATTICE_HOME/tickets/${ticket}-test"
  mkdir -p "$bdir"
  cat >"$bdir/README.md" <<EOF
# ${ticket} test binder

| Field | Value |
| --- | --- |
| status | ${status} |
| updated | 2026-09-01T00:00:00Z |
EOF
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
  # The wave atomically fail-closes the binder in-progress → stuck (A2.2).
  helper="$TEST_DIR/nopr.sh"
  FAKE_EXIT=none build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-U\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-U in-progress   # A2.2: real binder so commit flips atomically
  run env FAKE_EXIT=none bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "unknown: 1"
  printf '%s\n' "$output" | grep -qF "ok: 0"
  printf '%s\n' "$output" | grep -qF "failed: 0"
}

@test "A2.2: unknown atomically fail-closes binder status + ledger via commit" {
  # The unknown classification drives an ATOMIC binder-bound transition (spc-270
  # A2.2): transition-api.py commit flips | status | in-progress→stuck AND
  # appends the ledger entry in one locked transaction (not ledger-only record).
  helper="$TEST_DIR/nopr.sh"
  FAKE_EXIT=none build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-U\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-U in-progress
  run env FAKE_EXIT=none bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  # Atomic binder flip: | status | row is now stuck (not ledger-only).
  binder="$LATTICE_HOME/tickets/tkt-U-test/README.md"
  grep -qF '| status | stuck |' "$binder"
  grep -qF 'wait_reason' "$binder"
  # Ledger entry also written (edge legal: in-progress → stuck).
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

@test "A2.3: transition failure (bad binder continuity) → wave exits non-ok, node not settled" {
  # A binder whose status does NOT match the expected from-state (in-progress)
  # makes commit fail (continuity mismatch, rc=1). The wave must NOT swallow
  # it: WAVE_TRANSITION_FAIL bumps and the wave exits 1 (machine-decidable
  # non-ok) so the host cannot mistake a not-fail-closed node for success.
  helper="$TEST_DIR/nopr.sh"
  FAKE_EXIT=none build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-TF\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-TF closed   # actual status closed ≠ expected in-progress → commit rc=1
  run env FAKE_EXIT=none bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "unknown: 1"
  # The binder was NOT flipped to stuck (transition failed; status stays closed).
  binder="$LATTICE_HOME/tickets/tkt-TF-test/README.md"
  grep -qF '| status | closed |' "$binder"
}

@test "A2.5: malformed result artifact (exit=NaN) → failed, does not crash the wave" {
  # A garbage exit= value (non-numeric) is classified failed (≠ "0"), not ok
  # and not a crash — sed parsing is robust; the wave terminates bounded.
  helper="$TEST_DIR/malformed.sh"
  cat >"$helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--probe" ]]; then
  pid="$2"; [[ "$pid" =~ ^[0-9]+$ ]] || { echo "dead: $pid"; exit 0; }
  if kill -0 "$pid" 2>/dev/null; then echo "alive: $pid"; else echo "dead: $pid"; fi
  exit 0
fi
cwd=""; brief=""; state=""
while [[ $# -gt 0 ]]; do
  case "$1" in --cwd) cwd="$2"; shift 2 ;; --brief-file) brief="$2"; shift 2 ;; --state-file) state="$2"; shift 2 ;; *) shift ;; esac
done
[[ -n "${BATCH_RESULT_FILE:-}" ]] && printf 'exit=NaN\npr=\noid=\n' > "$BATCH_RESULT_FILE"
( cd "$cwd" && exec nohup sleep 4 >/dev/null 2>&1 ) &
pid=$!; disown "$pid" 2>/dev/null || true
echo "spawned: pid=$pid worktree=$cwd"
echo "state-file=$state"
EOF
  chmod +x "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-MF\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "failed: 1"
  printf '%s\n' "$output" | grep -qF "ok: 0"
}

@test "A2.4: uncorrelated agents --json failure does NOT veto ok" {
  # A worker that exits 0 + claims a verified PR is classified ok EVEN when a
  # global `claude agents --json` reports an unrelated failure — agents output
  # is advisory-only when uncorrelated to this ticket's PID/session (A2.4).
  helper="$TEST_DIR/ok.sh"
  FAKE_EXIT=0 FAKE_PR=42 FAKE_OID=abc1234 build_result_helper "$helper"
  fverify="$TEST_DIR/verify.sh"; build_fake_verify "$fverify" 42 abc1234
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-OK\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  # Fake claude on PATH that emits a global failure marker (unrelated ticket).
  fakeclaude="$TEST_DIR/claude"
  cat >"$fakeclaude" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "agents" && "${2:-}" == "--json" ]]; then
  printf '%s\n' '[{"id":"unrelated-session","status":"failed"}]'
  exit 0
fi
exit 0
EOF
  chmod +x "$fakeclaude"
  run env FAKE_EXIT=0 FAKE_PR=42 FAKE_OID=abc1234 PATH="$TEST_DIR:$PATH" CLAUDE_BIN="$fakeclaude" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$fverify" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok: 1"
  printf '%s\n' "$output" | grep -qF "failed: 0"
}

# ---------------------------------------------------------------------------
# spc-337 A6 (tkt-342) — failed fail-closes to stuck on the non-coordinator
# path; --batch-id activates the spine AND the per-barrier marker heartbeat.
# ---------------------------------------------------------------------------

# A fake batch-merge-gate.sh that logs every invocation's argv to $GATE_LOG.
build_fake_gate() {
  local f="$1"
  cat >"$f" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GATE_LOG:?GATE_LOG unset}"
exit 0
EOF
  chmod +x "$f"
}

@test "A6: failed (worker exit!=0) fail-closes binder to stuck on the non-coordinator path (fault test)" {
  # Fault: the worker ran past start-work (binder in-progress), then crashed
  # with exit=1. Without --batch-id (legacy path) the wave itself must flip
  # the binder in-progress → stuck + wait_reason: unblock — a crashed worker
  # never leaves its binder reading "active work" (FSM-2b).
  helper="$TEST_DIR/exit1.sh"
  FAKE_EXIT=1 build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-FS\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-FS in-progress
  run env FAKE_EXIT=1 bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "failed: 1"
  binder="$LATTICE_HOME/tickets/tkt-FS-test/README.md"
  grep -qF '| status | stuck |' "$binder"
  grep -qF '| wait_reason | unblock |' "$binder"
  ledger="$LATTICE_HOME/.transition-ledger/tkt-FS.jsonl"
  [ -f "$ledger" ]
  grep -qF '"from":"in-progress"' "$ledger"
  grep -qF '"to":"stuck"' "$ledger"
}

@test "A6: failed with a refused transition (wrong from-state) → wave exits non-ok, binder untouched" {
  helper="$TEST_DIR/exit1.sh"
  FAKE_EXIT=1 build_result_helper "$helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-FC\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-FC closed   # closed ≠ expected in-progress → commit rc=1
  run env FAKE_EXIT=1 bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "failed: 1"
  grep -qF '| status | closed |' "$LATTICE_HOME/tickets/tkt-FC-test/README.md"
}

@test "A6: --batch-id set → marker heartbeat: gate script called with --touch at the barrier" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  fake_gate="$TEST_DIR/fake-gate.sh"
  build_fake_gate "$fake_gate"
  export GATE_LOG="$TEST_DIR/gate.log"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-HB\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-HB in-progress   # the spine's unknown→stuck commit needs it
  run env GATE_LOG="$GATE_LOG" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$fast_helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf" \
    --batch-id "hb-batch-1" --layer 0 --wave 0 --gate-script "$fake_gate"
  [ "$status" -eq 0 ]
  # The spine was activated by --batch-id alone (no --coordinator needed).
  printf '%s\n' "$output" | grep -qF "coordinator: spine active batch=hb-batch-1"
  [ -f "$LATTICE_HOME/.coordinator/hb-batch-1.json" ]
  # The barrier touched the marker via the gate script.
  [ -f "$GATE_LOG" ]
  grep -qx -- '--touch' "$GATE_LOG"
}

@test "A6: no --batch-id → no heartbeat (gate script never called)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  fake_gate="$TEST_DIR/fake-gate.sh"
  build_fake_gate "$fake_gate"
  export GATE_LOG="$TEST_DIR/gate.log"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-NH\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run env GATE_LOG="$GATE_LOG" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$fast_helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf" \
    --gate-script "$fake_gate"
  [ "$status" -eq 0 ]
  [ ! -f "$GATE_LOG" ]
}

@test "A6: --batch-id with a missing gate script → warning only, wave still exits 0" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-MG\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-MG in-progress
  run bash "$WAVE" --manifest "$m" \
    --spawn-helper "$fast_helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf" \
    --batch-id "mg-batch-1" --gate-script "$TEST_DIR/does-not-exist.sh"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "warn: batch-merge-gate.sh not found"
  printf '%s\n' "$output" | grep -qF "marker heartbeat skipped"
}

@test "A6: --batch-id with the REAL gate script touches a --create'd marker (end-to-end heartbeat)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  gate="$(dirname "$WAVE")/../../finish-work/scripts/batch-merge-gate.sh"
  [ -f "$gate" ]
  export LATTICE_BATCH_GATE_HOME="$TEST_DIR/gate-home"
  mkdir -p "$LATTICE_BATCH_GATE_HOME"
  bash "$gate" --create --batch-id "e2e-hb" >/dev/null
  marker="$LATTICE_BATCH_GATE_HOME/.batch-work-active"
  touch -d '2000-01-01T00:00:00Z' "$marker" 2>/dev/null || touch -t 200001010000 "$marker"
  old_mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker")
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-E2\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-E2 in-progress
  run env LATTICE_BATCH_GATE_HOME="$LATTICE_BATCH_GATE_HOME" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$fast_helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf" \
    --batch-id "e2e-hb" --layer 0 --wave 0
  [ "$status" -eq 0 ]
  new_mtime=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker")
  [ "$new_mtime" -gt "$old_mtime" ]
  grep -qx 'batch-id: e2e-hb' "$marker"
}

@test "A6 (review cycle 2): coordinator path — failed with a refused transition → wave exits non-ok, node unsettled, binder untouched" {
  helper="$TEST_DIR/exit1.sh"
  FAKE_EXIT=1 build_result_helper "$helper"
  fake_gate="$TEST_DIR/fake-gate.sh"
  build_fake_gate "$fake_gate"
  export GATE_LOG="$TEST_DIR/gate.log"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-FC2\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  build_binder tkt-FC2 closed   # closed ≠ in-progress → commit refused → record-node rc≠0
  run env FAKE_EXIT=1 GATE_LOG="$GATE_LOG" bash "$WAVE" --manifest "$m" \
    --spawn-helper "$helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf" \
    --batch-id "fc-batch-2" --layer 0 --wave 0 --gate-script "$fake_gate"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF "coordinator: spine active batch=fc-batch-2"
  printf '%s\n' "$output" | grep -qF "transition-failed: tkt-FC2"
  grep -qF '| status | closed |' "$LATTICE_HOME/tickets/tkt-FC2-test/README.md"
  # node persisted as transition_failed and NOT settled
  python3 - "$LATTICE_HOME/.coordinator/fc-batch-2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
nodes = [n for l in d.get("dag", []) for w in l.get("waves", []) for n in w.get("nodes", [])]
n = next((x for x in nodes if x.get("ticket") == "tkt-FC2"), {})
assert n.get("status") == "transition_failed", (n, nodes)
assert "tkt-FC2" not in (d.get("settled_tickets") or []), d.get("settled_tickets")
PY
}

@test "tkt-463: run_with_timeout falls back to a bash watchdog when timeout(1) is absent (macOS)" {
  eval "$(sed -n '/^run_with_timeout()/,/^}$/p' "$WAVE")"
  export -f run_with_timeout
  # A PATH with only bash/sleep/kill-capable binaries and NO timeout/gtimeout.
  local nb="$TEST_DIR/nobin"; mkdir -p "$nb"
  for t in bash sleep true; do ln -s "$(command -v $t)" "$nb/$t"; done
  run bash -c "PATH='$nb' run_with_timeout 5 bash -c 'echo alive: 1'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "alive: 1"
  # the watchdog really kills an overrunning command (exit non-zero, < 5s)
  local t0 t1; t0=$(date +%s)
  run bash -c "PATH='$nb' run_with_timeout 1 sleep 5"
  t1=$(date +%s)
  [ "$status" -ne 0 ]
  [ $((t1 - t0)) -lt 4 ]
}

@test "tkt-463: grace probe reports a live surrogate as spawned even without timeout(1) on PATH" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-M\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  local nb="$TEST_DIR/nobin2"; mkdir -p "$nb"
  for t in bash sleep true date sed grep mktemp rm mkdir cat awk sort head tail tr wc uname python3 env nohup kill ls cut dirname basename touch; do
    b="$(command -v $t 2>/dev/null || true)"; [ -n "$b" ] && ln -sf "$b" "$nb/$t"
  done
  run env PATH="$nb" bash "$WAVE" --manifest "$m" --spawn-helper "$fast_helper" --verify-helper "$VERIFY" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "spawned: tkt-M"
  run bash -c "printf '%s\n' \"\$1\" | grep -c 'spawned-but-dead: tkt-M'" _ "$output"
  [ "$output" = "0" ]
}
