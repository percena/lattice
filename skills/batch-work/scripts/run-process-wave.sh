#!/usr/bin/env bash
# run-process-wave.sh — orchestrate ONE wave of `--spawn-mode process` tickets:
# spawn each ticket via spawn-ticket-process.sh (concurrency-capped, RAM-gated),
# poll PID liveness + per-ticket timebox at the barrier, print a Markdown report.
#
# This is the executable spine for batch-work process-mode SPAWN LAYER + LAYER
# BARRIER (ADR-008, spc-213 A3+A4). The host LLM session calls this per wave;
# the script returns a compact report row per ticket so the host's context is
# not flooded by N completion reports (ADR-008's core win).
#
# PROCESS-NODE FINAL STATE (spc-254 A1 — false-success closure). A PID that
# disappeared is NEVER named success. When a process exits within its timebox
# the barrier does NOT mark it `completed`; it classifies the node from FOUR
# signals and only then stamps a final state:
#
#   1. exit/result artifact — the worker writes `exit=<int>` (+ optional
#      `pr=<N>` / `oid=<hex>` claim) to $BATCH_RESULT_FILE (a per-ticket path
#      this script exports before each spawn; the spawn helper forwards it as
#      an inherited env var, so the worker — real `claude --bg` or a test
#      surrogate — can write it). An ABSENT artifact means the PID disappeared
#      without leaving a result → unknown (fail-closed), never success.
#   2. claude agents --json — enrichment, never the sole signal (schema-drift
#      tolerant; unavailable is not a blocker, an explicit failure is).
#   3. PID liveness — `kill -0` ground truth across macOS/Linux (alive=running,
#      dead=settled; settles within timebox → classify, past timebox → timeout).
#   4. verify-mutation --expected-oid — when the artifact claims a PR, this
#      script probes `verify-mutation.sh --pr <N> --expected-oid <OID>` IN-WAVE
#      (the shared helper landed by tkt-256). A phantom PR → failed.
#
# Classification: ok | failed | timeout | unknown.
#   ok      — exit==0 AND a PR claim AND verify-mutation verified AND agents
#             not-failed (agreement across the available signals).
#   failed  — exit!=0 (worker crashed) OR phantom PR (verify FAILED) OR
#             agents --json explicit failure.
#   timeout — killed past timebox (watchdog).
#   unknown — PID disappeared with no result artifact, OR exit==0 but no
#             verified PR claim (can't confirm success).
#
# failed|timeout|unknown ALL FAIL-CLOSE the binder to `stuck + wait_reason:
# unblock` via transition-api.py commit (tkt-255, spc-337 A6 / tkt-342 — a
# crashed worker never leaves its binder `in-progress`). The host then triages
# the stuck node.
#
# COORDINATOR SPINE (spc-254 A5 / spc-270 A3.1 / spc-337 A6): the coordinator
# activates when --batch-id is set (the canonical SKILL/flow invocation passes
# the marker's batch id); --coordinator only overrides the coordinator.py path.
# With the spine active the wave also touches the .batch-work-active marker at
# the end of each barrier (heartbeat, ADR-011) via batch-merge-gate.sh --touch.
#
# Usage:
#   run-process-wave.sh --manifest <path> [--concurrency N] [--ram-threshold GB]
#       [--state-file <path>] [--poll-interval sec] [--spawn-helper <path>]
#       [--verify-helper <path>] [--transition-api <path>] [--lattice-home <dir>]
#       [--batch-id <id> [--coordinator <path>] [--layer N] [--wave N]
#        [--gate-script <path>]] [--dry-run] [--report <path>]
#   run-process-wave.sh --self-test
#   run-process-wave.sh --help
#
# Manifest format (TSV; # lines + blank lines ignored):
#   # ticket<TAB>worktree<TAB>brief_file<TAB>timebox_min
#   tkt-219<TAB>/path/wt<TAB>/path/brief<TAB>60
#
# Exit codes:
#   0  wave settled (all tickets classified ok|failed|timeout|unknown); report printed
#   1  manifest missing/malformed / RAM below threshold before any spawn
#   2  usage error
#
# bash 3.2 portable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HELPER="$SCRIPT_DIR/spawn-ticket-process.sh"
LIB_DIR="$(cd "$SCRIPT_DIR/../../_lattice-lib/scripts" 2>/dev/null && pwd)"
DEFAULT_VERIFY="${LIB_DIR:-$SCRIPT_DIR}/verify-mutation.sh"
DEFAULT_TRANSITION_API="${LIB_DIR:-$SCRIPT_DIR}/transition-api.py"
COORD_DIR="$(cd "$SCRIPT_DIR/lib" 2>/dev/null && pwd)"
DEFAULT_COORDINATOR="${COORD_DIR:-$SCRIPT_DIR/lib}/coordinator.py"
# batch-merge-gate.sh lives with finish-work (it owns the marker's removal;
# spc-337 A6 gives it --create/--touch so creation + heartbeat share one helper).
GATE_DIR="$(cd "$SCRIPT_DIR/../../finish-work/scripts" 2>/dev/null && pwd)"
DEFAULT_GATE_SCRIPT="${GATE_DIR:-$SCRIPT_DIR/../../finish-work/scripts}/batch-merge-gate.sh"

usage() {
  cat <<EOF
usage: run-process-wave.sh --manifest <path> [options]
       run-process-wave.sh --self-test
       run-process-wave.sh --help

  --manifest <path>      TSV manifest: ticket<TAB>worktree<TAB>brief_file<TAB>timebox_min
                         (# comments + blank lines ignored). Worktrees must already
                         exist (created by the host via ensure-workspace).
  --concurrency N        Max concurrent spawns (default 3).
  --ram-threshold GB      Skip spawn if available RAM below this (default 10; 0 disables).
  --state-file <path>     Per-batch state file passed to the spawn helper.
  --poll-interval sec     Barrier poll interval (default 10).
  --spawn-helper <path>   spawn-ticket-process.sh path (default: sibling script).
  --verify-helper <path>  verify-mutation.sh path (default: _lattice-lib sibling).
                         Probes each claimed PR --expected-oid IN-WAVE (spc-254 A1).
  --transition-api <path> transition-api.py path (default: _lattice-lib sibling).
                         Records the failed|timeout|unknown→stuck fail-close flip.
  --lattice-home <dir>    Lattice home dir for the transition ledger (default:
                         \$LATTICE_HOME or .lattice).
  --batch-id <id>         Batch id (the .batch-work-active marker's id). Setting
                         it ACTIVATES the coordinator spine: the wave persists
                         DAG/layer/node-attempt/PID-PR-OID/marker-owner/
                         failure-class/resume-cursor to <state-home>/
                         .coordinator/<batch-id>.json (spc-254 A5, spc-270
                         A3.1) so a host restart resumes from the persisted
                         cursor without re-deriving, and touches the marker at
                         each barrier (heartbeat, ADR-011 / spc-337 A6). The
                         coordinator performs NO model inference (D4) — it
                         consumes the transition API (tkt-255) and this wave's
                         classification (tkt-257). Omit for the legacy
                         no-state path.
  --coordinator <path>    coordinator.py path override (default: sibling lib).
                         Only changes WHICH script the spine uses; it does not
                         activate the spine — --batch-id does.
  --gate-script <path>    batch-merge-gate.sh path override (default:
                         ../../finish-work/scripts sibling). Used for the
                         per-barrier marker --touch when --batch-id is set;
                         a missing gate script is a warning, never a failure.
  --layer <N>             DAG layer index this wave belongs to (forwarded to
                         the coordinator so resume knows which layer settled).
  --wave <N>              Wave index within the layer (forwarded to the
                         coordinator's resume cursor).
  --dry-run               Print the wave plan; do not spawn.
  --report <path>         Write the Markdown report to <path> (always also stdout).
EOF
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

# run_with_timeout <seconds> <cmd…> — GNU `timeout` when present (Linux),
# `gtimeout` (brew coreutils), else a bash watchdog. tkt-463: macOS ships no
# `timeout`, so every `timeout N bash helper --probe` failed and the wave
# reported every spawn as spawned-but-dead on the macOS CI matrix.
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@" & local cmd_pid=$!
    ( sleep "$secs"; kill "$cmd_pid" 2>/dev/null ) & local wd_pid=$!
    local rc=0
    wait "$cmd_pid" 2>/dev/null || rc=$?
    kill "$wd_pid" 2>/dev/null; wait "$wd_pid" 2>/dev/null || true
    return "$rc"
  fi
}

get_available_ram_gb() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local ps ps_free inactive speculative pagesize
    pagesize=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
    # vm_stat output: "Pages free: N." etc.
    ps=$(vm_stat 2>/dev/null || true)
    ps_free=$(printf '%s\n' "$ps" | awk '/Pages free/ {gsub(/[^0-9]/,"",$4); print $4}')
    inactive=$(printf '%s\n' "$ps" | awk '/Pages inactive/ {gsub(/[^0-9]/,"",$3); print $3}')
    speculative=$(printf '%s\n' "$ps" | awk '/Pages speculative/ {gsub(/[^0-9]/,"",$4); print $4}')
    echo $(( ( ${ps_free:-0} + ${inactive:-0} + ${speculative:-0} ) * pagesize / 1024 / 1024 / 1024 ))
  else
    local m
    m=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    echo $(( m / 1024 / 1024 ))
  fi
}

# Parse manifest into global arrays. Skips #/blank lines. Fails closed on
# malformed rows (must have exactly 4 fields). Sets M_COUNT (global); caller
# reads it. MUST be called in the current shell (not a subshell) so the arrays
# persist.
parse_manifest() {
  local f="$1"
  [[ -f "$f" ]] || { echo "error: manifest not found: $f" >&2; exit 1; }
  local line n=0 field_count
  M_TICKET=(); M_WT=(); M_BRIEF=(); M_TIMEBOX=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    field_count=$(printf '%s' "$line" | awk -F'\t' '{print NF}')
    [[ "$field_count" -eq 4 ]] || { echo "error: manifest row must be 4 TSV fields (ticket<TAB>worktree<TAB>brief_file<TAB>timebox_min); got $field_count: $line" >&2; exit 1; }
    M_TICKET+=("$(printf '%s' "$line" | awk -F'\t' '{print $1}')")
    M_WT+=("$(printf '%s' "$line" | awk -F'\t' '{print $2}')")
    M_BRIEF+=("$(printf '%s' "$line" | awk -F'\t' '{print $3}')")
    M_TIMEBOX+=("$(printf '%s' "$line" | awk -F'\t' '{print $4}')")
    n=$((n+1))
  done < "$f"
    M_COUNT=$n
}

# ---------------------------------------------------------------------------
# process-node classification (spc-254 A1 — false-success closure)
# ---------------------------------------------------------------------------
# Globals populated by run_wave before barrier_poll runs:
#   WAVE_RESULTS_DIR     per-ticket result-artifact dir
#   WAVE_VERIFY_HELPER   verify-mutation.sh path
#   WAVE_TRANSITION_API  transition-api.py path
#   WAVE_LATTICE_HOME    LATTICE_HOME for the transition ledger

# claude agents --json enrichment (best-effort; never the sole signal). Returns
# "failed" only when claude is on PATH AND `agents --json` carries an explicit
# failure marker; "" (empty = not a blocker) otherwise (unavailable/schema-drift).
probe_agents_json() {
  local pid="$1" ticket="$2"
  local claude_bin="${CLAUDE_BIN:-claude}"
  command -v "$claude_bin" >/dev/null 2>&1 || { echo ""; return 0; }
  local json
  json=$("$claude_bin" agents --json 2>/dev/null || true)
  [[ -n "$json" ]] || { echo ""; return 0; }
  # Coarse + schema-tolerant: any explicit failed/error/crashed status entry.
  # PID↔session matching is deferred (the spec treats agents --json as
  # enrichment, not ground truth); an explicit failure marker vetoes ok.
  if printf '%s' "$json" | grep -qE '"(status|state)"[[:space:]]*:[[:space:]]*"(failed|error|crashed)"'; then
    echo "failed"; return 0
  fi
  echo ""
}

# Record the failed|timeout|unknown fail-close: binder in-progress → stuck with
# wait_reason: unblock, via transition-api.py (tkt-255; spc-337 A6 adds
# failed). Best-effort — a missing/errored transition-api MUST NOT crash the
# wave (set -e guarded); it warns so the host's morning triage still sees the
# unrecorded stuck node in the report.
record_stuck() {
  local ticket="$1" reason="$2"
  [[ -f "$WAVE_TRANSITION_API" ]] || { echo "error: transition-api.py not found; cannot atomic-fail-close $ticket" >&2; return 1; }
  # Resolve the binder for this ticket under LATTICE_HOME. commit needs a real
  # binder to flip | status | atomically (A2.2). When none exists (test or
  # no-binder edge), fall back to ledger-only record so the stuck transition is
  # still journaled — this is degraded (not an A2.3 transition failure: there
  # was no binder to flip), so return 0 and do NOT bump WAVE_TRANSITION_FAIL.
  local binder="" d
  for d in "$WAVE_LATTICE_HOME"/tickets/${ticket}-*/; do
    [[ -f "${d}README.md" ]] && { binder="${d}README.md"; break; }
  done
  if [[ -z "$binder" ]]; then
    LATTICE_HOME="$WAVE_LATTICE_HOME" python3 "$WAVE_TRANSITION_API" record "$ticket" in-progress stuck system "$reason" \
      --trace "wait_reason: unblock" >/dev/null 2>&1 && return 0
    echo "warn: transition-api record (ledger-only fallback) failed for $ticket (no binder; ledger not written)" >&2
    return 1
  fi
  # Atomic binder-bound transition (spc-270 A2.2): commit wraps
  # prepare_commit_text + commit_transaction under the binder dir lock,
  # flipping status in-progress→stuck AND wait_reason:unblock AND appending
  # the ledger entry in one transaction. Returns the rc so the caller
  # fail-closes (A2.3) — a real binder-bound failure is never swallowed.
  LATTICE_HOME="$WAVE_LATTICE_HOME" python3 "$WAVE_TRANSITION_API" commit "$ticket" stuck system "$reason" \
    --from in-progress --wait-reason unblock --trace "wait_reason: unblock" >/dev/null 2>&1
  local rc=$?
  [[ "$rc" -ne 0 ]] && echo "error: atomic stuck transition FAILED for $ticket (rc=$rc; binder NOT fail-closed — host must stamp stuck manually)" >&2
  return $rc
}

# coordinator spine helpers (spc-254 A5). When WAVE_COORDINATOR is set, the
# wave persists DAG/layer/node-attempt/PID-PR-OID/marker-owner/failure-class/
# resume-cursor via coordinator.py. The coordinator performs NO model
# inference (D4) — it calls transition-api.py internally for the binder flip,
# so these helpers REPLACE record_stuck when the spine is active (no double
# ledger entry). Best-effort: a coordinator error warns, never crashes the wave.
coord_record_spawn() {
  local ticket="$1" pid="$2" wt="$3" brief="$4" timebox="$5"
  [[ -n "${WAVE_COORDINATOR:-}" ]] || return 0
  # tkt-471 A9: record-spawn failure is machine-fatal — a lost spawn record
  # means resume cannot recover the running node.
  if ! LATTICE_HOME="$WAVE_LATTICE_HOME" python3 "$WAVE_COORDINATOR" record-spawn \
    --batch-id "$WAVE_BATCH_ID" --ticket "$ticket" --layer "$WAVE_LAYER" \
    --wave "$WAVE_WAVE" --pid "$pid" --worktree "$wt" --brief-file "$brief" \
    --timebox "$timebox" --lattice-home "$WAVE_LATTICE_HOME" >/dev/null 2>&1; then
    echo "error: coordinator record-spawn FAILED for $ticket — machine-fatal (tkt-471 A9)" >&2
    return 1
  fi
}

# coord_record_node <ticket> <status> [pid] [pr] [oid] [reason]
# status ∈ {ok,failed,timeout,unknown,spawned-but-dead,workspace-failed}.
# The coordinator calls transition-api commit for failed/timeout/unknown
# (→stuck + wait_reason: unblock, BEFORE settle — spc-270 A3.4 + spc-337 A6).
# ok/spawned-but-dead/workspace-failed persist the failure class only (the
# worker owns ok→pr-open; the other two never reached start-work, so the
# binder is still queued). When the spine is NOT active, the caller falls back
# to record_stuck for the same failed/timeout/unknown fail-close.
coord_record_node() {
  local ticket="$1" status="$2" pid="${3:-}" pr="${4:-}" oid="${5:-}" reason="${6:-}"
  [[ -n "${WAVE_COORDINATOR:-}" ]] || return 0
  local -a args=(record-node --batch-id "$WAVE_BATCH_ID" --ticket "$ticket" \
    --status "$status" --failure-class "$status" --transition-api "$WAVE_TRANSITION_API" \
    --lattice-home "$WAVE_LATTICE_HOME")
  [[ -n "$pid" ]] && args+=(--pid "$pid")
  [[ -n "$pr" ]] && args+=(--pr "$pr")
  [[ -n "$oid" ]] && args+=(--oid "$oid")
  [[ -n "$reason" ]] && args+=(--reason "$reason")
  # spc-337 A6 review cycle 2: a record-node failure on the canonical
  # (--batch-id) path is the coordinator's fail-closed signal — the node is
  # NOT settled (transition_failed) — so the wave must exit machine-decidably
  # non-ok exactly like the legacy record_stuck branch (A2.3 / A3.4). Swallowing
  # it with a warning left rc=0 while SKILL/flow promised non-zero.
  if ! LATTICE_HOME="$WAVE_LATTICE_HOME" python3 "$WAVE_COORDINATOR" "${args[@]}" >/dev/null 2>&1; then
    WAVE_TRANSITION_FAIL=$(( WAVE_TRANSITION_FAIL + 1 ))
    echo "${status}-transition-failed: ${ticket} (coordinator record-node failed — node not settled; host must stamp stuck)" >&2
  fi
}

# heartbeat_marker — touch the .batch-work-active marker's mtime at the end of
# each barrier (ADR-011 amendment, spc-337 A6 / tkt-342) so the mtime-based
# stale-marker GC never reaps a live batch. Only when the spine is active
# (WAVE_BATCH_ID set — the marker is keyed by that batch id). Best-effort: a
# missing gate script or an absent marker is a warning, never a wave failure.
heartbeat_marker() {
  [[ -n "${WAVE_BATCH_ID:-}" ]] || return 0
  if [[ ! -f "${WAVE_GATE_SCRIPT:-}" ]]; then
    echo "warn: batch-merge-gate.sh not found at ${WAVE_GATE_SCRIPT:-<unset>}; marker heartbeat skipped for batch $WAVE_BATCH_ID" >&2
    return 0
  fi
  bash "$WAVE_GATE_SCRIPT" --touch >/dev/null \
    || echo "warn: marker heartbeat (--touch) failed for batch $WAVE_BATCH_ID (stale-marker GC may reap it)" >&2
}

# After a wave barrier settles, advance the resume cursor so a restart
# picks up at the NEXT wave, not re-running the settled one.
coord_advance() {
  [[ -n "${WAVE_COORDINATOR:-}" ]] || return 0
  # tkt-471 A9: cursor persistence failure is machine-fatal — a lost cursor
  # means restart replays the settled wave.
  if ! LATTICE_HOME="$WAVE_LATTICE_HOME" python3 "$WAVE_COORDINATOR" advance-cursor \
    --batch-id "$WAVE_BATCH_ID" --layer "$WAVE_LAYER" --wave "$WAVE_WAVE" \
    --lattice-home "$WAVE_LATTICE_HOME" >/dev/null 2>&1; then
    echo "error: coordinator advance-cursor FAILED — machine-fatal (tkt-471 A9)" >&2
    return 1
  fi
}

# classify_node <i> — redefine a settled process node's final state from the
# four signals. Called from barrier_poll when `kill -0` reports the PID dead
# (settled within timebox). Sets STATUS[i] ∈ {ok,failed,unknown} and records
# the stuck ledger flip for unknown. (timeout is set by the caller before kill.)
classify_node() {
  local i="$1"
  local ticket="${M_TICKET[i]}" pid="${PIDS[i]}"
  local rfile="$WAVE_RESULTS_DIR/${ticket}.result"
  local exit_code="" pr="" oid="" agents="" verify=""
  local reason=""

  # 1. exit/result artifact (written by the worker to $BATCH_RESULT_FILE).
  if [[ -f "$rfile" ]]; then
    exit_code=$(sed -n 's/^exit=//p' "$rfile" 2>/dev/null | head -1)
    pr=$(sed -n 's/^pr=//p' "$rfile" 2>/dev/null | head -1)
    oid=$(sed -n 's/^oid=//p' "$rfile" 2>/dev/null | head -1)
  fi

  # 2. claude agents --json enrichment.
  agents=$(probe_agents_json "$pid" "$ticket")

  # 3. verify-mutation --expected-oid (when a PR is claimed).
  if [[ -n "$pr" && -n "$oid" ]]; then
    if bash "$WAVE_VERIFY_HELPER" --pr "$pr" --expected-oid "$oid" >/dev/null 2>&1; then
      verify="verified"
    else
      verify="failed"
    fi
  fi

  # 4. classify — a PID that disappeared is NEVER success.
  if [[ -z "$exit_code" ]]; then
    STATUS[i]="unknown"; reason="no result artifact; PID $pid disappeared without exit/result (never success)"
  elif [[ "$exit_code" != "0" ]]; then
    STATUS[i]="failed"; reason="worker exit=$exit_code (non-zero)"
  elif [[ "$verify" == "failed" ]]; then
    STATUS[i]="failed"; reason="verify-mutation FAILED for claimed pr=$pr oid=$oid (phantom PR)"
  elif [[ "$exit_code" == "0" && -n "$pr" && "$verify" == "verified" ]]; then
    STATUS[i]="ok"; reason="exit=0 + verify verified"
    # agents --json is advisory-only when uncorrelated to this ticket's
    # PID/session (spc-270 A2.4): a global unrelated agent failure cannot
    # veto ok. PID↔session correlation is not yet wired, so never
    # hard-classify failed on uncorrelated agents output.
    [[ "$agents" == "failed" ]] && reason+="; advisory: uncorrelated agents --json failure (not vetoed)"
  else
    STATUS[i]="unknown"; reason="exit=0 but no verified PR claim (pr=${pr:-none} oid=${oid:-none} verify=${verify:-none})"
  fi
  ENDS[i]=$(now_epoch)
  echo "${STATUS[i]}: ${ticket} pid=$pid ($reason)" >&2

  # failed|unknown fail-close the binder to stuck + wait_reason: unblock
  # (timeout does the same from barrier_poll). When the coordinator spine is
  # active (spc-254 A5), coord_record_node persists ALL settled statuses
  # (ok/failed/timeout/unknown) AND records the binder flip via transition-api
  # internally — replacing record_stuck so there is no double ledger entry.
  # When the spine is off, the legacy record_stuck path runs for failed AND
  # unknown (spc-337 A6: a crashed worker / phantom PR must not leave the
  # binder in-progress — same set as coordinator.py STUCK_STATUSES).
  if [[ -n "${WAVE_COORDINATOR:-}" ]]; then
    coord_record_node "$ticket" "${STATUS[i]}" "$pid" "$pr" "$oid" "$reason"
  elif [[ "${STATUS[i]}" == "unknown" || "${STATUS[i]}" == "failed" ]]; then
    # Atomic fail-close (A2.2). A transition failure prevents node settle
    # and makes the wave exit machine-decidably non-ok (A2.3): the node
    # stays unsolved and WAVE_TRANSITION_FAIL bumps so run_wave exits 1.
    if ! record_stuck "$ticket" "$reason"; then
      WAVE_TRANSITION_FAIL=$(( WAVE_TRANSITION_FAIL + 1 ))
      reason+="; ATOMIC TRANSITION FAILED — node not settled (host must stamp stuck)"
      echo "${STATUS[i]}-transition-failed: ${ticket} pid=$pid ($reason)" >&2
    fi
  fi
}

run_wave() {
  local manifest="" concurrency=3 ram_thr=10 state_file="" poll_interval=10 spawn_helper="$DEFAULT_HELPER" dry=0 report=""
  local verify_helper="$DEFAULT_VERIFY" transition_api="$DEFAULT_TRANSITION_API" lattice_home="${LATTICE_HOME:-.lattice}"
  local coordinator="" batch_id="" layer=0 wave=0 gate_script="$DEFAULT_GATE_SCRIPT"
  local layers_json=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest) manifest="$2"; shift 2 ;;
      --concurrency) concurrency="$2"; shift 2 ;;
      --ram-threshold) ram_thr="$2"; shift 2 ;;
      --state-file) state_file="$2"; shift 2 ;;
      --poll-interval) poll_interval="$2"; shift 2 ;;
      --spawn-helper) spawn_helper="$2"; shift 2 ;;
      --verify-helper) verify_helper="$2"; shift 2 ;;
      --transition-api) transition_api="$2"; shift 2 ;;
      --lattice-home) lattice_home="$2"; shift 2 ;;
      --coordinator) coordinator="$2"; shift 2 ;;
      --batch-id) batch_id="$2"; shift 2 ;;
      --gate-script) gate_script="$2"; shift 2 ;;
      --layer) layer="$2"; shift 2 ;;
      --wave) wave="$2"; shift 2 ;;
      --layers-json) layers_json="$2"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --report) report="$2"; shift 2 ;;
      *) echo "usage error: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
    esac
  done
  # Default the coordinator path. --coordinator ONLY overrides which script the
  # spine runs; activation is decided by --batch-id below (one truth, spc-337
  # A6 — the earlier "opt-in via --coordinator" comment was stale).
  coordinator="${coordinator:-$DEFAULT_COORDINATOR}"

  [[ -n "$manifest" ]] || { echo "usage error: --manifest is required" >&2; usage >&2; exit 2; }
  [[ -f "$spawn_helper" ]] || { echo "error: spawn-helper not found: $spawn_helper" >&2; exit 1; }
  [[ -f "$verify_helper" ]] || { echo "error: verify-helper not found: $verify_helper" >&2; exit 1; }
  [[ "$concurrency" =~ ^[0-9]+$ && "$concurrency" -ge 1 ]] || { echo "error: --concurrency must be a positive int" >&2; exit 2; }
  # Coordinator wiring (spc-254 A5 / spc-270 A3.1 / spc-337 A6). The spine
  # activates when --batch-id is supplied (the canonical SKILL/flow invocation
  # passes the marker's batch id): the wave persists DAG/layer/node-attempt/
  # PID-PR-OID/marker-owner/failure-class/resume-cursor so a host restart
  # resumes without re-deriving, and touches the .batch-work-active marker at
  # each barrier (heartbeat). --coordinator only overrides the script path;
  # --batch-id without --coordinator uses the sibling default. No --batch-id ⇒
  # legacy no-state path (unchanged). The coordinator performs NO model
  # inference (D4); it consumes the transition API (tkt-255) + this wave's
  # four-signal classification (tkt-257 ok|failed|timeout|unknown).
  WAVE_COORDINATOR=""
  WAVE_BATCH_ID=""
  WAVE_LAYER=0
  WAVE_WAVE=0
  WAVE_GATE_SCRIPT="$gate_script"
  if [[ -n "$batch_id" ]]; then
    [[ -f "$coordinator" ]] || { echo "error: coordinator not found: $coordinator (required when --batch-id is set; spc-270 A3.1 default-on)" >&2; exit 1; }
    # tkt-471 A9: init failure prevents spawn (was || true).
    if ! LATTICE_HOME="$lattice_home" python3 "$coordinator" init --batch-id "$batch_id" --lattice-home "$lattice_home" >/dev/null 2>&1; then
      echo "error: coordinator init FAILED for batch=$batch_id — aborting (tkt-471 A9: machine-fatal)" >&2
      exit 1
    fi
    # tkt-471 A7: persist the complete DAG before any spawn. The host must pass
    # --layers-json <path> so all future waves are durable. If --layers-json is
    # not provided, verify load-dag was already called (plan_loaded in state).
    if [[ -n "${layers_json:-}" && -f "$layers_json" ]]; then
      if ! LATTICE_HOME="$lattice_home" python3 "$coordinator" load-dag --batch-id "$batch_id" --layers-json "$layers_json" --lattice-home "$lattice_home" >/dev/null 2>&1; then
        echo "error: coordinator load-dag FAILED for batch=$batch_id — aborting (tkt-471 A7)" >&2
        exit 1
      fi
    fi
    WAVE_COORDINATOR="$coordinator"
    WAVE_BATCH_ID="$batch_id"
    WAVE_LAYER="$layer"
    WAVE_WAVE="$wave"
    echo "coordinator: spine active batch=$batch_id layer=$layer wave=$wave (state: $lattice_home/.coordinator/$batch_id.json)" >&2
  fi

  local count
  parse_manifest "$manifest"
  count=$M_COUNT
  [[ "$count" -gt 0 ]] || { echo "manifest has 0 tickets" >&2; exit 1; }

  local _state_auto=0
  [[ -n "$state_file" ]] || { state_file=$(mktemp -t batch-wave-state.XXXXXX); _state_auto=1; }
  # Shell globals (not run_wave locals) so the EXIT trap still sees them after
  # run_wave returns. _WAVE_STATE_FILE is set only when the wave owns the temp
  # (auto-mktemp); WAVE_RESULTS_DIR is always set (per-ticket result-artifact
  # dir, spc-254 A1) and the trap cleans it. Both guarded with `${var:-}` so
  # `set -u` can't fire (tkt-257: the prior unconditional trap made every
  # --state-file wave exit non-zero via an unbound var).
  _WAVE_STATE_FILE=""
  if [[ "$_state_auto" -eq 1 ]]; then
    _WAVE_STATE_FILE="$state_file"
  fi
  trap '[[ -n "${_WAVE_STATE_FILE:-}" ]] && rm -f -- "$_WAVE_STATE_FILE"; [[ -n "${WAVE_RESULTS_DIR:-}" ]] && rm -rf -- "$WAVE_RESULTS_DIR"' EXIT

  # Per-ticket result-artifact dir (spc-254 A1). Each spawn exports
  # BATCH_RESULT_FILE=<dir>/<ticket>.result so the worker (real claude --bg or
  # a test surrogate) can write its exit/result + PR claim; classify_node reads
  # it at the barrier.
  WAVE_RESULTS_DIR=$(mktemp -d -t bw-results.XXXXXX)
  WAVE_TRANSITION_FAIL=0  # spc-270 A2.3: transition failures → non-ok exit
  WAVE_VERIFY_HELPER="$verify_helper"
  WAVE_TRANSITION_API="$transition_api"
  WAVE_LATTICE_HOME="$lattice_home"

  if [[ "$dry" -eq 1 ]]; then
    echo "dry-run: wave plan ($count tickets, concurrency=$concurrency, ram-threshold=$ram_thr, poll=${poll_interval}s, helper=$spawn_helper)"
    for i in $(seq 0 $((count-1))); do
      printf '  %s\twt=%s\tbrief=%s\ttimebox=%smin\n' "${M_TICKET[i]}" "${M_WT[i]}" "${M_BRIEF[i]}" "${M_TIMEBOX[i]}"
    done
    exit 0
  fi

  # Pre-spawn RAM gate (once for the wave).
  if [[ "$ram_thr" -gt 0 ]]; then
    local ram; ram=$(get_available_ram_gb)
    if [[ "$ram" -lt "$ram_thr" ]]; then
      echo "error: available RAM ${ram} GB < threshold ${ram_thr} GB; aborting wave (fail closed)" >&2
      exit 1
    fi
  fi

  # Spawn in concurrency-capped batches. PIDs + start epochs tracked per ticket.
  local -a PIDS=() STARTS=() STATUS=() ENDS=()
  local i
  for i in $(seq 0 $((count-1))); do PIDS[i]=""; STARTS[i]=0; STATUS[i]="pending"; ENDS[i]=0; done

  local spawned_so_far=0
  while [[ "$spawned_so_far" -lt "$count" ]]; do
    # Re-check RAM before each concurrency batch.
    if [[ "$ram_thr" -gt 0 ]]; then
      local ram; ram=$(get_available_ram_gb)
      if [[ "$ram" -lt "$ram_thr" ]]; then
        echo "warn: RAM ${ram} GB < threshold ${ram_thr} mid-wave; stopping further spawns (in-flight continues)" >&2
        break
      fi
    fi
    local batch_end=$(( spawned_so_far + concurrency ))
    [[ "$batch_end" -gt "$count" ]] && batch_end=$count
    local j
    for (( j=spawned_so_far; j<batch_end; j++ )); do
      if [[ ! -d "${M_WT[j]}" ]]; then
        echo "error: worktree missing for ${M_TICKET[j]}: ${M_WT[j]} (host must ensure-workspace first)" >&2
        STATUS[j]="workspace-failed"; coord_record_node "${M_TICKET[j]}" "workspace-failed" "" "" "" "worktree missing"
        continue
      fi
      # Export the per-ticket result path so the spawn helper forwards it
      # (via its `env`-prefixed exec) to the worker, which writes exit/pr/oid.
      export BATCH_RESULT_FILE="$WAVE_RESULTS_DIR/${M_TICKET[j]}.result"
      local out
      if out=$(bash "$spawn_helper" --cwd "${M_WT[j]}" --brief-file "${M_BRIEF[j]}" --state-file "$state_file" 2>&1); then
        local pid
        pid=$(printf '%s\n' "$out" | sed -n 's/^spawned: pid=\([0-9]*\) .*/\1/p')
        [[ "$pid" =~ ^[0-9]+$ ]] || { STATUS[j]="workspace-failed"; coord_record_node "${M_TICKET[j]}" "workspace-failed" "" "" "" "spawn produced no pid"; echo "warn: spawn produced no pid for ${M_TICKET[j]}: $out" >&2; continue; }
        PIDS[j]="$pid"; STARTS[j]=$(now_epoch); STATUS[j]="running"
        # Persist the spawn (running) state to the coordinator spine so a
        # restart knows this node attempted (spc-254 A5).
        coord_record_spawn "${M_TICKET[j]}" "$pid" "${M_WT[j]}" "${M_BRIEF[j]}" "${M_TIMEBOX[j]}"
        # Grace-period re-check: an immediate-crash spawn (auth/OOM) would
        # otherwise be reported `completed` by the barrier's first poll —
        # indistinguishable from success mid-wave (tkt-242 L2). Probe again
        # after a short grace; a dead PID here is `spawned-but-dead`, not a
        # silent completed. Mirrors the spawn helper's own grace re-check.
        sleep "${SPAWN_GRACE_SEC:-0.3}"
        if run_with_timeout "${PROBE_TIMEOUT_SEC:-8}" bash "$spawn_helper" --probe "$pid" 2>/dev/null | grep -q "^alive:"; then
          echo "spawned: ${M_TICKET[j]} pid=$pid" >&2
        else
          STATUS[j]="spawned-but-dead"; ENDS[j]=$(now_epoch)
          coord_record_node "${M_TICKET[j]}" "spawned-but-dead" "$pid" "" "" "died within ${SPAWN_GRACE_SEC:-0.3}s grace"
          echo "spawned-but-dead: ${M_TICKET[j]} pid=$pid (died within ${SPAWN_GRACE_SEC:-0.3}s grace)" >&2
        fi
      else
        STATUS[j]="workspace-failed"; echo "warn: spawn failed for ${M_TICKET[j]}: $out" >&2
        coord_record_node "${M_TICKET[j]}" "workspace-failed" "" "" "" "spawn command failed"
      fi
    done
    spawned_so_far=$batch_end

    # Barrier: poll this batch (and any still-running from prior batches) until
    # all running tickets settle or trip their timebox.
    barrier_poll "$j" "$poll_interval"
  done

  # If concurrency >= count, the whole wave spawned in one batch; barrier ran
  # inside the loop. If spawns broke early on RAM, ensure remaining barrier.
  barrier_poll "$count" "$poll_interval"

  # The wave settled — advance the coordinator resume cursor so a host
  # restart picks up at the NEXT wave, never re-running this settled one
  # (spc-254 A5: resume without re-deriving from artifacts).
  coord_advance

  emit_report "$count" "$report"
  # A2.3: a transition failure makes the wave exit machine-decidably non-ok
  # so the host cannot mistake a not-fail-closed node for success. An `if`
  # (not `&&`) keeps the function's return 0 when no transition failed.
  if [[ "$WAVE_TRANSITION_FAIL" -gt 0 ]]; then exit 1; fi
}

# Poll all "running" tickets until none running. timebox per ticket (minutes).
# A PID that dies within its timebox is CLASSIFIED (ok|failed|unknown) — never
# silently marked completed (spc-254 A1). Past-timebox → killed + timeout.
barrier_poll() {
  local count="$1" interval="$2"
  while true; do
    local any_running=0
    for i in $(seq 0 $((count-1))); do
      [[ "${STATUS[i]}" == "running" ]] || continue
      any_running=1
      local pid="${PIDS[i]}"
      if run_with_timeout "${PROBE_TIMEOUT_SEC:-8}" bash "$spawn_helper" --probe "$pid" 2>/dev/null | grep -q "^alive:"; then
        # still alive — check timebox
        local elapsed=$(( $(now_epoch) - STARTS[i] ))
        local limit=$(( M_TIMEBOX[i] * 60 ))
        if [[ "$elapsed" -gt "$limit" ]]; then
          kill "$pid" 2>/dev/null || true
          STATUS[i]="timeout"; ENDS[i]=$(now_epoch)
          local treason="watchdog timeout (elapsed ${elapsed}s > timebox ${limit}s)"
          echo "timeout: ${M_TICKET[i]} pid=$pid ($treason)" >&2
          # timeout fail-closes the binder to stuck + wait_reason: unblock
          # (FSM-2b, tkt-132) — via the spine when active, else record_stuck
          # (spc-337 A6: same failed|timeout|unknown set on both paths).
          if [[ -n "${WAVE_COORDINATOR:-}" ]]; then
            coord_record_node "${M_TICKET[i]}" "timeout" "$pid" "" "" "$treason"
          elif ! record_stuck "${M_TICKET[i]}" "$treason"; then
            WAVE_TRANSITION_FAIL=$(( WAVE_TRANSITION_FAIL + 1 ))
            echo "timeout-transition-failed: ${M_TICKET[i]} pid=$pid ($treason; ATOMIC TRANSITION FAILED — node not settled (host must stamp stuck))" >&2
          fi
        fi
      else
        # PID dead (settled within timebox) → classify from the four signals.
        classify_node "$i"
      fi
    done
    [[ "$any_running" -eq 0 ]] && break
    sleep "$interval"
  done
  # Barrier settled → marker heartbeat (no-op unless --batch-id is set).
  heartbeat_marker
}

emit_report() {
  local count="$1" report="${2:-}"
  local lines=()
  lines+=("# batch-work process-wave report")
  lines+=("")
  lines+=("ran: $(now_iso)")
  lines+=("")
  lines+=("| ticket | pid | worktree | status | timebox_min | duration_s |")
  lines+=("| --- | --- | --- | --- | --- | --- |")
  local ok=0 failed=0 timeout=0 unknown=0 spawned_dead=0 wf=0
  for i in $(seq 0 $((count-1))); do
    local dur=0
    [[ "${ENDS[i]}" -gt 0 ]] && dur=$(( ENDS[i] - STARTS[i] ))
    lines+=("| ${M_TICKET[i]} | ${PIDS[i]:-—} | ${M_WT[i]} | ${STATUS[i]} | ${M_TIMEBOX[i]} | $dur |")
    case "${STATUS[i]}" in
      ok) ok=$((ok+1)) ;;
      failed) failed=$((failed+1)) ;;
      timeout) timeout=$((timeout+1)) ;;
      unknown) unknown=$((unknown+1)) ;;
      spawned-but-dead) spawned_dead=$((spawned_dead+1)) ;;
      workspace-failed) wf=$((wf+1)) ;;
    esac
  done
  lines+=("")
  lines+=("## Summary")
  lines+=("- spawned: $((count - wf - spawned_dead))")
  lines+=("- ok: $ok")
  lines+=("- failed: $failed")
  lines+=("- timeout: $timeout")
  lines+=("- unknown: $unknown")
  lines+=("- workspace-failed: $wf")
  lines+=("- spawned-but-dead: $spawned_dead")
  lines+=("")
  lines+=("Classification (spc-254 A1 / spc-270 A2 / spc-337 A6): ok requires exit=0 + verify-mutation --expected-oid verified; agents --json is advisory-only when uncorrelated (A2.4); failed|timeout|unknown atomically fail-close the binder to stuck + wait_reason: unblock via transition-api commit (A2.2, A6); a transition failure leaves the wave exit non-ok (A2.3).")
  local report_text
  report_text=$(printf '%s\n' "${lines[@]}")
  printf '%s\n' "$report_text"
  if [[ -n "$report" ]]; then
    local dir; dir=$(dirname "$report"); [[ -d "$dir" ]] || mkdir -p "$dir"
    printf '%s\n' "$report_text" > "$report"
    echo "(report written to $report)" >&2
  fi
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

self_test() {
  local fail=0
  chk() { local label="$1"; shift; if "$@"; then echo "PASS: $label"; else echo "FAIL: $label"; fail=$((fail+1)); fi; }

  # A fake spawn helper that spawns `sleep 2` surrogates so the wave logic is
  # exercised without real claude. It writes NO result artifact → the node is
  # classified `unknown` (PID disappeared without exit/result — never success),
  # which exercises the fail-close path.
  local fake_helper sf lhome
  fake_helper=$(mktemp -t bw-fakehelper.XXXXXX)
  sf=$(mktemp -t bw-fakestate.XXXXXX)
  lhome=$(mktemp -d -t bw-lhome.XXXXXX)
  cat > "$fake_helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --probe)
    pid="$2"
    [[ "$pid" =~ ^[0-9]+$ ]] || { echo "dead: $pid"; exit 0; }
    if kill -0 "$pid" 2>/dev/null; then echo "alive: $pid"; else echo "dead: $pid"; fi
    exit 0 ;;
  *)
    cwd=""; brief=""; state=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --cwd) cwd="$2"; shift 2 ;;
        --brief-file) brief="$2"; shift 2 ;;
        --state-file) state="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    ( cd "$cwd" && exec nohup sleep 2 >/dev/null 2>&1 ) &
    pid=$!; disown "$pid" 2>/dev/null || true
    printf 'started\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$state"
    echo "spawned: pid=$pid worktree=$cwd"
    echo "state-file=$state"
    ;;
esac
EOF
  chmod +x "$fake_helper"

  # T1: manifest parsing — 4 TSV fields, skips comments
  t1() {
    local m
    m=$(mktemp -t bw-manifest.XXXXXX)
    printf '# header\n\ntkt-1\t/tmp/a\t/tmp/b1\t1\ntkt-2\t/tmp/b\t/tmp/b2\t1\n' > "$m"
    parse_manifest "$m"; local r=$?; [[ $r -eq 0 && "$M_COUNT" -eq 2 ]]; r=$?
    rm -f "$m"; return $r
  }
  chk "T1: manifest parse 4-TSV + skip comments" t1

  # T2: malformed row fails closed
  t2() {
    local m
    m=$(mktemp -t bw-manifest.XXXXXX)
    printf 'tkt-1 /tmp/a /tmp/b1 1\n' > "$m"   # spaces, not tabs → 1 field
    ( parse_manifest "$m" ) >/dev/null 2>&1; local r=$?; rm -f "$m"
    [[ $r -ne 0 ]]
  }
  chk "T2: malformed manifest row fails closed" t2

  # T3: dry-run prints plan, no spawn
  t3() {
    local m wt brief
    m=$(mktemp -t bw-manifest.XXXXXX)
    wt=$(mktemp -d -t bw-wt.XXXXXX)
    brief=$(mktemp -t bw-brief.XXXXXX); echo x > "$brief"
    printf 'tkt-1\t%s\t%s\t1\n' "$wt" "$brief" > "$m"
    local out
    out=$(bash "$0" --manifest "$m" --spawn-helper "$fake_helper" --verify-helper "$DEFAULT_VERIFY" --ram-threshold 0 --dry-run 2>/dev/null) || { rm -f "$m" "$brief"; rm -rf "$wt"; return 1; }
    rm -f "$m" "$brief"; rm -rf "$wt"
    [[ "$out" == *"dry-run: wave plan"* && "$out" == *"tkt-1"* ]]
  }
  chk "T3: --dry-run plan no-spawn" t3

  # T4: full wave — 2 sleep surrogates, settle within timebox. No result
  #     artifact → both classified `unknown` (never `completed`); the
  #     fail-close records a stuck ledger entry per ticket (spc-254 A1).
  t4() {
    local m wt1 wt2 b1 b2 rep out
    m=$(mktemp -t bw-manifest.XXXXXX)
    wt1=$(mktemp -d -t bw-wt1.XXXXXX); wt2=$(mktemp -d -t bw-wt2.XXXXXX)
    b1=$(mktemp -t bw-b1.XXXXXX); echo x > "$b1"
    b2=$(mktemp -t bw-b2.XXXXXX); echo x > "$b2"
    rep=$(mktemp -t bw-rep.XXXXXX)
    printf 'tkt-A\t%s\t%s\t1\ntkt-B\t%s\t%s\t1\n' "$wt1" "$b1" "$wt2" "$b2" > "$m"
    out=$(bash "$0" --manifest "$m" --spawn-helper "$fake_helper" --verify-helper "$DEFAULT_VERIFY" --transition-api "$DEFAULT_TRANSITION_API" --lattice-home "$lhome" --ram-threshold 0 --state-file "$sf" --poll-interval 1 --concurrency 2 --report "$rep" 2>/dev/null) || { rm -f "$m" "$b1" "$b2" "$rep"; rm -rf "$wt1" "$wt2"; return 1; }
    local r=$?
    [[ "$out" == *"unknown: 2"* ]] && [[ "$out" == *"tkt-A"* && "$out" == *"tkt-B"* ]]
    r=$?
    rm -f "$m" "$b1" "$b2" "$rep"; rm -rf "$wt1" "$wt2"
    return $r
  }
  chk "T4: wave spawn→poll→classify (2 surrogates → unknown, never completed)" t4

  # T5: timebox timeout — surrogate sleeps longer than timebox → killed+timeout
  #     (use a fake helper that sleeps 30s; timebox 0 min trips immediately.)
  t5() {
    local slow_helper m wt b rep out
    slow_helper=$(mktemp -t bw-slowhelper.XXXXXX)
    cat > "$slow_helper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--probe" ]]; then pid="$2"; if kill -0 "$pid" 2>/dev/null; then echo "alive: $pid"; else echo "dead: $pid"; fi; exit 0; fi
cwd=""; brief=""; state=""
while [[ $# -gt 0 ]]; do case "$1" in --cwd) cwd="$2"; shift 2 ;; --brief-file) brief="$2"; shift 2 ;; --state-file) state="$2"; shift 2 ;; *) shift ;; esac; done
( cd "$cwd" && exec nohup sleep 30 >/dev/null 2>&1 ) &
pid=$!; disown "$pid" 2>/dev/null || true
echo "spawned: pid=$pid worktree=$cwd"
echo "state-file=$state"
EOF
    chmod +x "$slow_helper"
    m=$(mktemp -t bw-manifest.XXXXXX)
    wt=$(mktemp -d -t bw-wt.XXXXXX)
    b=$(mktemp -t bw-b.XXXXXX); echo x > "$b"
    rep=$(mktemp -t bw-rep.XXXXXX)
    # timebox 0 min → limit 0s → any elapsed trips immediately
    printf 'tkt-T\t%s\t%s\t0\n' "$wt" "$b" > "$m"
    out=$(bash "$0" --manifest "$m" --spawn-helper "$slow_helper" --verify-helper "$DEFAULT_VERIFY" --transition-api "$DEFAULT_TRANSITION_API" --lattice-home "$lhome" --ram-threshold 0 --state-file "$sf" --poll-interval 1 --concurrency 1 --report "$rep" 2>/dev/null) || true
    rm -f "$m" "$b" "$rep" "$slow_helper"; rm -rf "$wt"
    [[ "$out" == *"timeout: 1"* ]]
  }
  chk "T5: timebox timeout → kill + timeout status" t5

  # T6: missing --manifest fails closed (exit 2)
  t6() { bash "$0" --spawn-helper "$fake_helper" --verify-helper "$DEFAULT_VERIFY" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
  chk "T6: missing --manifest fails closed" t6

  # T7: missing worktree → workspace-failed (not a hard crash)
  t7() {
    local m b rep out
    m=$(mktemp -t bw-manifest.XXXXXX)
    b=$(mktemp -t bw-b.XXXXXX); echo x > "$b"
    rep=$(mktemp -t bw-rep.XXXXXX)
    printf 'tkt-X\t/nonexistent/wt\t%s\t1\n' "$b" > "$m"
    out=$(bash "$0" --manifest "$m" --spawn-helper "$fake_helper" --verify-helper "$DEFAULT_VERIFY" --ram-threshold 0 --state-file "$sf" --poll-interval 1 --report "$rep" 2>/dev/null) || true
    rm -f "$m" "$b" "$rep"
    [[ "$out" == *"workspace-failed: 1"* ]]
  }
  chk "T7: missing worktree → workspace-failed (not crash)" t7

  rm -f "$fake_helper" "$sf"; rm -rf "$lhome"
  echo ""
  if [[ $fail -eq 0 ]]; then echo "✅ run-process-wave.sh --self-test passed"
  else echo "❌ run-process-wave.sh --self-test FAILED ($fail failure(s))"; exit 1; fi
}

main() {
  if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
  case "${1:-}" in
    --self-test) self_test ;;
    *) run_wave "$@" ;;
  esac
}

main "$@"
