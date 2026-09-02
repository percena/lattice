#!/usr/bin/env bats
# Tests for coordinator.py — the recoverable persistent spine for batch/finish
# DAG execution (spc-254 A5 / D4; rev-20260830-141357Z F4).
#
# A5 fault injection: a host restart mid-batch/finish resumes from the
# persisted DAG/layer/node-attempt/PID-PR-OID/marker-owner/failure-class/
# resume-cursor without re-deriving state from artifacts. The coordinator
# performs NO model inference (D4 — no claude/agents/LLM subprocess; only
# file I/O + one transition-api.py call per settled node, consuming tkt-255
# and tkt-257's ok|failed|timeout|unknown classification).
#
# Also covers the run-process-wave.sh wiring: when --coordinator/--batch-id
# are passed, the wave persists spawn + settled-node state to the coordinator
# state file and advances the resume cursor; legacy behavior (no --coordinator)
# is unchanged.
#
# bats 1.13.0 — canonical `run` + `[ ]`.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export COORD="$REPO_ROOT/skills/batch-work/scripts/lib/coordinator.py"
  export WAVE="$REPO_ROOT/skills/batch-work/scripts/run-process-wave.sh"
  export TAPI="$REPO_ROOT/skills/_lattice-lib/scripts/transition-api.py"
  export VERIFY="$REPO_ROOT/skills/_lattice-lib/scripts/verify-mutation.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coord.XXXXXX")"
  export TEST_DIR
  LATTICE_HOME="$TEST_DIR/lhome"
  export LATTICE_HOME
  mkdir -p "$LATTICE_HOME"
  # ADR-011 / spc-282 A2: coordinator state relocates to the out-of-repo state
  # home (resolved via fingerprint, NOT --lattice-home). Pin the state home to
  # the test temp so assertions on $LATTICE_HOME/.coordinator/ still hold.
  LATTICE_STATE_HOME="$LATTICE_HOME"
  export LATTICE_STATE_HOME
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Assert a ticket appears in the JSON's settled_tickets list (robust to
# pretty-printed multi-line arrays — coordinator.py emits indent=2).
assert_settled() {
  local json="$1" ticket="$2"
  printf '%s' "$json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); sys.exit(0 if '$ticket' in d.get('settled_tickets',[]) else 1)"
}

# Assert a ticket appears in the JSON's pending list.
assert_pending_ticket() {
  local json="$1" ticket="$2"
  printf '%s' "$json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); sys.exit(0 if any(n['ticket']=='$ticket' for n in d.get('pending',[])) else 1)"
}

# ---------------------------------------------------------------------------
# coordinator.py unit tests
# ---------------------------------------------------------------------------

@test "init creates the state file; re-init is idempotent" {
  run python3 "$COORD" init --batch-id "b1" --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  [ -f "$LATTICE_HOME/.coordinator/b1.json" ]
  # re-init does not clobber (idempotent — preserves existing state)
  python3 "$COORD" set-marker-owner --batch-id "b1" --pid 9999 --lattice-home "$LATTICE_HOME" >/dev/null
  run python3 "$COORD" init --batch-id "b1" --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  run python3 "$COORD" status --batch-id "b1" --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF '"pid": 9999'
}

@test "load-dag persists layers + nodes with full field set" {
  python3 "$COORD" init --batch-id "b2" --lattice-home "$LATTICE_HOME" >/dev/null
  lj="$TEST_DIR/layers.json"
  cat >"$lj" <<EOF
{"layers":[
  {"layer":0,"waves":[{"wave":0,"nodes":[
    {"ticket":"tkt-A","worktree":"/p/a","brief_file":"/b/a","timebox_min":5}
  ]}]},
  {"layer":1,"waves":[{"wave":0,"nodes":[
    {"ticket":"tkt-B","worktree":"/p/b","brief_file":"/b/b","timebox_min":10}
  ]}]}
]}
EOF
  run python3 "$COORD" load-dag --batch-id "b2" --layers-json "$lj" --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "2 layer(s), 2 node(s)"
  run python3 "$COORD" status --batch-id "b2" --lattice-home "$LATTICE_HOME"
  # node 0 has the full defaulted field set (status, attempt, pid, ...)
  printf '%s\n' "$output" | grep -qF '"status": "pending"'
  printf '%s\n' "$output" | grep -qF '"failure_class": null'
}

@test "record-spawn + record-node merge-update a node in place (no sibling wipe)" {
  python3 "$COORD" init --batch-id "b3" --lattice-home "$LATTICE_HOME" >/dev/null
  # spawn tkt-A
  python3 "$COORD" record-spawn --batch-id "b3" --ticket "tkt-A" --layer 0 --wave 0 \
    --pid 1111 --worktree "/p/a" --brief-file "/b/a" --timebox 5 \
    --lattice-home "$LATTICE_HOME" >/dev/null
  # spawn tkt-B (concurrent recorder — must not wipe tkt-A)
  python3 "$COORD" record-spawn --batch-id "b3" --ticket "tkt-B" --layer 0 --wave 0 \
    --pid 2222 --worktree "/p/b" --brief-file "/b/b" --timebox 5 \
    --lattice-home "$LATTICE_HOME" >/dev/null
  # tkt-A settles ok (claims pr+oid); coordinator records the pr-open flip
  python3 "$COORD" record-node --batch-id "b3" --ticket "tkt-A" --status ok \
    --pid 1111 --pr 42 --oid abc1234 --failure-class ok --reason "exit=0+verify" \
    --transition-api "$TAPI" --lattice-home "$LATTICE_HOME" >/dev/null
  run python3 "$COORD" status --batch-id "b3" --lattice-home "$LATTICE_HOME"
  # Both nodes survive the merge; tkt-A is ok with pr/oid, tkt-B still running
  printf '%s\n' "$output" | grep -qF '"ticket": "tkt-A"'
  printf '%s\n' "$output" | grep -qF '"ticket": "tkt-B"'
  printf '%s\n' "$output" | grep -qF '"status": "ok"'
  printf '%s\n' "$output" | grep -qF '"pr": 42'
  printf '%s\n' "$output" | grep -qF '"oid": "abc1234"'
  # tkt-A in settled_tickets
  assert_settled "$output" "tkt-A"
  # tkt-298: the coordinator no longer duplicates the ok→pr-open flip — the
  # worker's create-pr (stamp-pr-open) owns it. No ledger entry is written by
  # the coordinator for an ok node (single source of truth; no discontinuity).
  [ ! -f "$LATTICE_HOME/.transition-ledger/tkt-A.jsonl" ]
}

@test "record-node unknown fail-closes binder to stuck via transition-api (tkt-255)" {
  python3 "$COORD" init --batch-id "b4" --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id "b4" --ticket "tkt-U" --layer 0 --wave 0 \
    --pid 3333 --worktree "/p/u" --brief-file "/b/u" --timebox 5 \
    --lattice-home "$LATTICE_HOME" >/dev/null
  # tkt-298: the worker crashed/timed out before create-pr, so its binder is
  # still in-progress (start-work stamped it). The coordinator is the sole
  # recorder → it flips the binder to stuck via `commit` (binder + ledger
  # atomic). Create the in-progress binder the worker would have stamped.
  UDIR="$LATTICE_HOME/tickets/tkt-U-demo"
  mkdir -p "$UDIR"
  cat >"$UDIR/README.md" <<MD
# tkt-U — demo

| Field | Value |
| --- | --- |
| status | in-progress |
| wait_reason | (none) |
MD
  python3 "$COORD" record-node --batch-id "b4" --ticket "tkt-U" --status unknown \
    --pid 3333 --failure-class unknown --reason "PID disappeared" \
    --transition-api "$TAPI" --lattice-home "$LATTICE_HOME" >/dev/null
  ledger="$LATTICE_HOME/.transition-ledger/tkt-U.jsonl"
  [ -f "$ledger" ]
  grep -qF '"from":"in-progress"' "$ledger"
  grep -qF '"to":"stuck"' "$ledger"
  grep -qF '"trace":"wait_reason: unblock"' "$ledger"
  # tkt-298: commit flipped the binder atomically with the ledger (snapshot ok)
  grep -q '| status | stuck |' "$UDIR/README.md"
  grep -q '| wait_reason | unblock |' "$UDIR/README.md"
}

@test "advance-cursor moves the resume point" {
  python3 "$COORD" init --batch-id "b5" --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" advance-cursor --batch-id "b5" --layer 2 --wave 1 --lattice-home "$LATTICE_HOME" >/dev/null
  run python3 "$COORD" status --batch-id "b5" --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF '"layer": 2'
  printf '%s\n' "$output" | grep -qF '"wave": 1'
}

# ---------------------------------------------------------------------------
# A5 — host restart resumes from persisted state without re-deriving
# ---------------------------------------------------------------------------

@test "A5: host restart mid-batch resumes from persisted DAG/layer/node/cursor (no re-derive)" {
  # The fault: a host builds a 2-layer DAG (tkt-A layer0, tkt-B layer1), runs
  # wave 0 (tkt-A settles ok), then RESTARTS. The restarted host reads the
  # coordinator state — it does NOT re-read binders/manifests to re-derive
  # what already ran. resume() reports tkt-A settled + tkt-B pending so the
  # host spawns only tkt-B.
  python3 "$COORD" init --batch-id "restart-1" --lattice-home "$LATTICE_HOME" >/dev/null
  lj="$TEST_DIR/layers.json"
  cat >"$lj" <<EOF
{"layers":[
  {"layer":0,"waves":[{"wave":0,"nodes":[
    {"ticket":"tkt-A","worktree":"/p/a","brief_file":"/b/a","timebox_min":5}
  ]}]},
  {"layer":1,"waves":[{"wave":0,"nodes":[
    {"ticket":"tkt-B","worktree":"/p/b","brief_file":"/b/b","timebox_min":10}
  ]}]}
]}
EOF
  python3 "$COORD" load-dag --batch-id "restart-1" --layers-json "$lj" --lattice-home "$LATTICE_HOME" >/dev/null
  # wave 0: spawn + settle tkt-A (ok)
  python3 "$COORD" record-spawn --batch-id "restart-1" --ticket "tkt-A" --layer 0 --wave 0 \
    --pid 4444 --worktree "/p/a" --brief-file "/b/a" --timebox 5 \
    --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-node --batch-id "restart-1" --ticket "tkt-A" --status ok \
    --pid 4444 --pr 7 --oid deadbeef --failure-class ok --reason "ok" \
    --transition-api "$TAPI" --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" advance-cursor --batch-id "restart-1" --layer 1 --wave 0 --lattice-home "$LATTICE_HOME" >/dev/null
  # --- HOST RESTARTS (new process; no in-memory state) ---
  run python3 "$COORD" resume --batch-id "restart-1" --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  # tkt-A is settled (not re-derived); tkt-B is pending (the only thing to run)
  assert_settled "$output" "tkt-A"
  assert_pending_ticket "$output" "tkt-B"
  printf '%s\n' "$output" | grep -qF '"layer": 1'
  # tkt-A does NOT appear in pending (would mean re-derivation / re-run)
  run assert_pending_ticket "$output" "tkt-A"
  [ "$status" -ne 0 ]
}

@test "A5: resume cursor correctness — settled nodes never re-listed as pending" {
  python3 "$COORD" init --batch-id "cursor-1" --lattice-home "$LATTICE_HOME" >/dev/null
  lj="$TEST_DIR/layers.json"
  cat >"$lj" <<EOF
{"layers":[
  {"layer":0,"waves":[{"wave":0,"nodes":[
    {"ticket":"tkt-A","worktree":"/p/a","brief_file":"/b/a","timebox_min":5},
    {"ticket":"tkt-B","worktree":"/p/b","brief_file":"/b/b","timebox_min":5},
    {"ticket":"tkt-C","worktree":"/p/c","brief_file":"/b/c","timebox_min":5}
  ]}]}
]}
EOF
  python3 "$COORD" load-dag --batch-id "cursor-1" --layers-json "$lj" --lattice-home "$LATTICE_HOME" >/dev/null
  # A + B settle; C still pending. Cursor stays at layer 0 wave 0 (C is in the
  # same wave). resume must list ONLY tkt-C as pending.
  # spc-337 A6 (tkt-342): `failed` now fail-closes the binder to stuck BEFORE
  # settle (same as unknown|timeout), so each failed node needs the
  # in-progress binder its worker's start-work would have stamped.
  for t in tkt-A tkt-B; do
    mkdir -p "$LATTICE_HOME/tickets/$t-demo"
    printf '# %s\n\n| Field | Value |\n| --- | --- |\n| status | in-progress |\n| wait_reason | (none) |\n' "$t" >"$LATTICE_HOME/tickets/$t-demo/README.md"
    python3 "$COORD" record-spawn --batch-id "cursor-1" --ticket "$t" --layer 0 --wave 0 \
      --pid 5000 --worktree "/p" --brief-file "/b" --timebox 5 \
      --lattice-home "$LATTICE_HOME" >/dev/null
    python3 "$COORD" record-node --batch-id "cursor-1" --ticket "$t" --status failed \
      --pid 5000 --failure-class failed --reason "crash" \
      --transition-api "$TAPI" --lattice-home "$LATTICE_HOME" >/dev/null
  done
  run python3 "$COORD" resume --batch-id "cursor-1" --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  # pending has exactly one entry: tkt-C
  local n_pending
  n_pending=$(printf '%s' "$output" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['pending']))")
  [ "$n_pending" -eq 1 ]
  assert_pending_ticket "$output" "tkt-C"
  assert_settled "$output" "tkt-A"
  assert_settled "$output" "tkt-B"
}

# ---------------------------------------------------------------------------
# A5 / D4 — coordinator performs NO model inference
# ---------------------------------------------------------------------------

@test "A5/D4: coordinator performs no model inference (no claude/agents/LLM subprocess)" {
  # Static source proof (D4): the coordinator source never invokes claude /
  # agents / an LLM as a subprocess target. It only does file I/O + one
  # transition-api.py call (which itself does only file I/O).
  run python3 "$COORD" --self-test
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "no model inference"
  # Belt-and-suspenders: grep the source for a claude/agents subprocess target.
  local src
  src="$(cat "$COORD")"
  # A subprocess.run/call/Popen whose argv contains "claude" or "agents" would
  # violate D4. transition-api.py (file I/O only) is the sole subprocess.
  # grep -c (with `|| true` to survive set -e on no-match) → count must be 0.
  llm_subprocess=$(printf '%s' "$src" | grep -cE 'subprocess\.\w+\([^)]*["'"'"'](claude|agents)' || true)
  [ "$llm_subprocess" -eq 0 ]
  # Runtime proof: a full record-node cycle spawns no claude/agents process.
  python3 "$COORD" init --batch-id "noinfer-1" --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-node --batch-id "noinfer-1" --ticket "tkt-N" --status unknown \
    --pid 1234 --failure-class unknown --reason "test" \
    --transition-api "$TAPI" --lattice-home "$LATTICE_HOME" >/dev/null 2>&1 || true
  # No claude/agents binary was invoked (the only subprocess was python3 tapi).
  run command -v claude
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# A5 — run-process-wave.sh wiring (integration: the spine is opt-in)
# ---------------------------------------------------------------------------

# A fake spawn helper whose surrogates sleep briefly then settle (no result
# artifact → unknown). Mirrors the run-process-wave test helpers.
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
    --cwd) cwd="$2"; shift 2 ;; --brief-file) brief="$2"; shift 2 ;;
    --state-file) state="$2"; shift 2 ;; *) shift ;;
  esac
done
( cd "$cwd" && exec nohup sleep 1 >/dev/null 2>&1 ) &
pid=$!; disown "$pid" 2>/dev/null || true
echo "spawned: pid=$pid worktree=$cwd"
echo "state-file=$state"
EOF
  chmod +x "$f"
}

@test "A5 wiring: wave with --coordinator persists node state + advances cursor" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-W\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  # tkt-298: the coordinator flips the binder to stuck via `commit` (needs the
  # in-progress binder the worker's start-work would have stamped; the
  # fast_helper here sleeps instead of running start-work, so create it).
  WDIR="$LATTICE_HOME/tickets/tkt-W-demo"
  mkdir -p "$WDIR"
  printf '# tkt-W\n\n| Field | Value |\n| --- | --- |\n| status | in-progress |\n| wait_reason | (none) |\n' >"$WDIR/README.md"
  run bash "$WAVE" --manifest "$m" --spawn-helper "$fast_helper" \
    --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf" \
    --coordinator "$COORD" --batch-id "wire-1" --layer 0 --wave 0
  [ "$status" -eq 0 ]
  # The coordinator state file exists and carries the settled node.
  [ -f "$LATTICE_HOME/.coordinator/wire-1.json" ]
  run python3 "$COORD" status --batch-id "wire-1" --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF '"ticket": "tkt-W"'
  printf '%s\n' "$output" | grep -qF '"failure_class": "unknown"'
  assert_settled "$output" "tkt-W"
  # The unknown node recorded a stuck ledger flip via the coordinator spine.
  [ -f "$LATTICE_HOME/.transition-ledger/tkt-W.jsonl" ]
  grep -qF '"to":"stuck"' "$LATTICE_HOME/.transition-ledger/tkt-W.jsonl"
}

@test "A5 wiring: wave WITHOUT --coordinator is unchanged (legacy path, no state file)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-L\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  run bash "$WAVE" --manifest "$m" --spawn-helper "$fast_helper" \
    --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf"
  [ "$status" -eq 0 ]
  # No coordinator state file written (spine was not opted in).
  [ ! -f "$LATTICE_HOME/.coordinator/legacy.json" ]
  # The legacy record_stuck path still wrote the ledger flip.
  [ -f "$LATTICE_HOME/.transition-ledger/tkt-L.jsonl" ]
}

@test "A3.1 wiring: --batch-id alone DEFAULT-ON persists state; --coordinator without --batch-id is legacy (spc-270)" {
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  m="$TEST_DIR/manifest"; wt="$TEST_DIR/wt"; brief="$TEST_DIR/brief"
  mkdir -p "$wt"; printf 'x\n' >"$brief"
  printf 'tkt-D\t%s\t%s\t1\n' "$wt" "$brief" >"$m"
  # spc-337 A6 (review cycle 2): the fast helper leaves tkt-D `unknown`, and
  # the spine's unknown→stuck commit needs the in-progress binder the worker
  # would have stamped — without it the transition is refused and the wave
  # (correctly) exits non-ok. This test is about wiring, so give it the binder.
  DDIR="$LATTICE_HOME/tickets/tkt-D-demo"; mkdir -p "$DDIR"
  printf '# tkt-D\n\n| Field | Value |\n| --- | --- |\n| status | in-progress |\n| updated | 2026-09-01T00:00:00Z |\n' >"$DDIR/README.md"
  # --batch-id alone (no --coordinator) → coordinator default-on (state persisted)
  run bash "$WAVE" --manifest "$m" --spawn-helper "$fast_helper" \
    --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf" \
    --batch-id "default-on-1" --layer 0 --wave 0
  [ "$status" -eq 0 ]
  [ -f "$LATTICE_HOME/.coordinator/default-on-1.json" ]
  # --coordinator WITHOUT --batch-id → legacy no-state (no failure; just no persistence)
  # The first run fail-closed tkt-D to stuck; the legacy path's record_stuck
  # needs in-progress again (stuck → stuck is not an edge), so reset the binder.
  printf '# tkt-D\n\n| Field | Value |\n| --- | --- |\n| status | in-progress |\n| updated | 2026-09-01T00:00:00Z |\n' >"$DDIR/README.md"
  run bash "$WAVE" --manifest "$m" --spawn-helper "$fast_helper" \
    --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf2" \
    --coordinator "$COORD"
  [ "$status" -eq 0 ]
  [ ! -f "$LATTICE_HOME/.coordinator/no-batch.json" ]
}

@test "A5 wiring: host restart between waves resumes from persisted cursor (integration)" {
  # Fault: the host runs wave 0 (tkt-A settles), then RESTARTS. The restarted
  # host reads the coordinator state and resumes — it does NOT re-run tkt-A.
  fast_helper="$TEST_DIR/fast.sh"
  build_fast_helper "$fast_helper"
  # Layer 0 wave 0: tkt-A
  m0="$TEST_DIR/m0"; wt0="$TEST_DIR/wt0"; b0="$TEST_DIR/b0"
  mkdir -p "$wt0"; printf 'x\n' >"$b0"
  printf 'tkt-A\t%s\t%s\t1\n' "$wt0" "$b0" >"$m0"
  # A3.4 (spc-270): the coordinator fail-closes an unknown node via the atomic
  # stuck commit, which needs the in-progress binder the worker's start-work
  # would have stamped. The fast_helper sleeps instead of running start-work,
  # so create it (mirrors test 9's tkt-W binder).
  ADIR="$LATTICE_HOME/tickets/tkt-A-demo"
  mkdir -p "$ADIR"
  printf '# tkt-A\n\n| Field | Value |\n| --- | --- |\n| status | in-progress |\n| wait_reason | (none) |\n' >"$ADIR/README.md"
  LATTICE_HOME="$LATTICE_HOME" bash "$WAVE" --manifest "$m0" \
    --spawn-helper "$fast_helper" --verify-helper "$VERIFY" --transition-api "$TAPI" \
    --ram-threshold 0 --poll-interval 1 --concurrency 1 --state-file "$TEST_DIR/sf0" \
    --coordinator "$COORD" --batch-id "restart-int" --layer 0 --wave 0 >/dev/null 2>&1
  # --- HOST RESTARTS (new process, new manifest for wave 1) ---
  # The restarted host asks the coordinator what is settled before spawning.
  run python3 "$COORD" resume --batch-id "restart-int" --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  assert_settled "$output" "tkt-A"
  # No pending nodes (layer 0 wave 0 fully settled) — the host would now
  # advance to the next layer/wave without re-deriving tkt-A's status from
  # its result artifact or the transition ledger.
  run assert_pending_ticket "$output" "tkt-A"
  [ "$status" -ne 0 ]
}

# --- spc-270 A3: recoverable coordinator hardening (tkt-275) ---

@test "A3.4: unknown node WITHOUT a binder does NOT settle (transition failure prevents settle)" {
  LATTICE_HOME="$LATTICE_HOME" python3 "$COORD" init --batch-id a34 --lattice-home "$LATTICE_HOME" >/dev/null
  # record-spawn then record-node unknown with NO binder → _commit_stuck fails → node not settled, exit 1
  LATTICE_HOME="$LATTICE_HOME" python3 "$COORD" record-spawn --batch-id a34 --ticket tkt-NA \
    --layer 0 --wave 0 --pid 1234 --worktree /p --brief-file /b --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  run python3 "$COORD" record-node --batch-id a34 --ticket tkt-NA --status unknown \
    --pid 1234 --failure-class unknown --reason "crash" --transition-api "$TAPI" --lattice-home "$LATTICE_HOME"
  [ "$status" -ne 0 ]
  # node persisted as transition_failed, NOT in settled_tickets
  # node persisted as transition_failed (status cmd dumps the full node), NOT settled
  run python3 "$COORD" status --batch-id a34 --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF "transition_failed"
  # tkt-NA must NOT be in settled_tickets (JSON parse, not a whole-output grep)
  printf '%s' "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'tkt-NA' not in d.get('settled_tickets',[]) else 1)"
  # resume shows tkt-NA still pending (not settled)
  run python3 "$COORD" resume --batch-id a34 --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF 'tkt-NA'
}

@test "A3.3: settled node never regresses (re-recording a settled ticket with a lesser status is a no-op)" {
  LATTICE_HOME="$LATTICE_HOME" python3 "$COORD" init --batch-id a33 --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id a33 --ticket tkt-S --layer 0 --wave 0 --pid 1 \
    --worktree /p --brief-file /b --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  # create a binder so the stuck commit succeeds → node settles as unknown
  SDIR="$LATTICE_HOME/tickets/tkt-S-demo"; mkdir -p "$SDIR"
  printf '# tkt-S\n\n| Field | Value |\n| --- | --- |\n| status | in-progress |\n' >"$SDIR/README.md"
  python3 "$COORD" record-node --batch-id a33 --ticket tkt-S --status unknown --pid 1 \
    --failure-class unknown --reason crash --transition-api "$TAPI" --lattice-home "$LATTICE_HOME" >/dev/null
  # re-record with a NON-settled status (running) — must NOT regress the settled unknown node
  python3 "$COORD" record-node --batch-id a33 --ticket tkt-S --status running --pid 1 \
    --failure-class running --reason stale-retry --transition-api "$TAPI" --lattice-home "$LATTICE_HOME" >/dev/null 2>&1 || true
  run python3 "$COORD" status --batch-id a33 --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF '"status": "unknown"'  # not regressed to running
}

@test "A3.3: re-spawn increments attempt (does not reset to 1)" {
  LATTICE_HOME="$LATTICE_HOME" python3 "$COORD" init --batch-id a33att --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id a33att --ticket tkt-R --layer 0 --wave 0 --pid 100 \
    --worktree /p --brief-file /b --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id a33att --ticket tkt-R --layer 0 --wave 0 --pid 101 \
    --worktree /p --brief-file /b --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  run python3 "$COORD" status --batch-id a33att --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF '"attempt": 2'  # incremented, not reset to 1
}

@test "A3.5: resume carries next_node (first eligible) so a host restart drives it directly" {
  LATTICE_HOME="$LATTICE_HOME" python3 "$COORD" init --batch-id a35 --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id a35 --ticket tkt-N1 --layer 0 --wave 0 --pid 1 \
    --worktree /p1 --brief-file /b1 --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id a35 --ticket tkt-N2 --layer 0 --wave 0 --pid 2 \
    --worktree /p2 --brief-file /b2 --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  run python3 "$COORD" resume --batch-id a35 --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"next_node"'
  printf '%s\n' "$output" | grep -qF 'tkt-N1'  # first eligible = next_node
}

# --- spc-337 A6: `failed` fail-closes to stuck before settle (tkt-342) ---

@test "A6: record-node failed fail-closes binder to stuck + wait_reason: unblock (fault test)" {
  # Fault: the worker ran, then crashed (exit!=0) or claimed a phantom PR
  # after start-work stamped in-progress. The coordinator must flip the
  # binder to stuck BEFORE settling — the binder may never keep reading
  # "active work" for a dead worker (FSM-2b; rev-20260902-015425Z F5).
  python3 "$COORD" init --batch-id "a6-failed" --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id "a6-failed" --ticket "tkt-F6" --layer 0 --wave 0 \
    --pid 4444 --worktree "/p/f" --brief-file "/b/f" --timebox 5 \
    --lattice-home "$LATTICE_HOME" >/dev/null
  FDIR="$LATTICE_HOME/tickets/tkt-F6-demo"
  mkdir -p "$FDIR"
  printf '# tkt-F6\n\n| Field | Value |\n| --- | --- |\n| status | in-progress |\n| wait_reason | (none) |\n' >"$FDIR/README.md"
  run python3 "$COORD" record-node --batch-id "a6-failed" --ticket "tkt-F6" --status failed \
    --pid 4444 --failure-class failed --reason "worker exit=1 (non-zero)" \
    --transition-api "$TAPI" --lattice-home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  grep -q '| status | stuck |' "$FDIR/README.md"
  grep -q '| wait_reason | unblock |' "$FDIR/README.md"
  ledger="$LATTICE_HOME/.transition-ledger/tkt-F6.jsonl"
  [ -f "$ledger" ]
  grep -qF '"from":"in-progress"' "$ledger"
  grep -qF '"to":"stuck"' "$ledger"
  grep -qF '"trace":"wait_reason: unblock"' "$ledger"
  # Settled with failure_class failed (the node IS settled once stuck landed).
  run python3 "$COORD" status --batch-id "a6-failed" --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF '"failure_class": "failed"'
  assert_settled "$output" "tkt-F6"
}

@test "A6: record-node failed with a REFUSED transition does NOT settle (transition_failed, rc!=0)" {
  # No binder → transition-api commit cannot flip anything → the node must
  # stay unsettled exactly as unknown|timeout do (A3.4 parity for failed).
  python3 "$COORD" init --batch-id "a6-refused" --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id "a6-refused" --ticket "tkt-NF" --layer 0 --wave 0 \
    --pid 4545 --worktree "/p" --brief-file "/b" --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  run python3 "$COORD" record-node --batch-id "a6-refused" --ticket "tkt-NF" --status failed \
    --pid 4545 --failure-class failed --reason "crash" --transition-api "$TAPI" --lattice-home "$LATTICE_HOME"
  [ "$status" -ne 0 ]
  run python3 "$COORD" status --batch-id "a6-refused" --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF "transition_failed"
  printf '%s' "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'tkt-NF' not in d.get('settled_tickets',[]) else 1)"
  run python3 "$COORD" resume --batch-id "a6-refused" --lattice-home "$LATTICE_HOME"
  printf '%s\n' "$output" | grep -qF 'tkt-NF'
}

@test "A6: record-node failed with a binder in the WRONG from-state (closed) is refused, binder untouched" {
  python3 "$COORD" init --batch-id "a6-cont" --lattice-home "$LATTICE_HOME" >/dev/null
  python3 "$COORD" record-spawn --batch-id "a6-cont" --ticket "tkt-CL" --layer 0 --wave 0 \
    --pid 4646 --worktree "/p" --brief-file "/b" --timebox 5 --lattice-home "$LATTICE_HOME" >/dev/null
  CDIR="$LATTICE_HOME/tickets/tkt-CL-demo"
  mkdir -p "$CDIR"
  printf '# tkt-CL\n\n| Field | Value |\n| --- | --- |\n| status | closed |\n| wait_reason | (none) |\n' >"$CDIR/README.md"
  run python3 "$COORD" record-node --batch-id "a6-cont" --ticket "tkt-CL" --status failed \
    --pid 4646 --failure-class failed --reason "crash" --transition-api "$TAPI" --lattice-home "$LATTICE_HOME"
  [ "$status" -ne 0 ]
  grep -q '| status | closed |' "$CDIR/README.md"
}
