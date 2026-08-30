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
# Status from PID alone is "completed" (process exited within timebox) or
# "timeout" (still alive past timebox → killed). Whether completed work
# actually opened a PR is the host's job — it runs verify-mutation.sh per
# ticket afterward (spawn-brief item 6). This script owns spawn + poll + report.
#
# Usage:
#   run-process-wave.sh --manifest <path> [--concurrency N] [--ram-threshold GB]
#       [--state-file <path>] [--poll-interval sec] [--spawn-helper <path>]
#       [--dry-run] [--report <path>]
#   run-process-wave.sh --self-test
#   run-process-wave.sh --help
#
# Manifest format (TSV; # lines + blank lines ignored):
#   # ticket<TAB>worktree<TAB>brief_file<TAB>timebox_min
#   tkt-219<TAB>/path/wt<TAB>/path/brief<TAB>60
#
# Exit codes:
#   0  wave settled (all tickets completed or timed out); report printed
#   1  manifest missing/malformed / RAM below threshold before any spawn
#   2  usage error
#
# bash 3.2 portable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HELPER="$SCRIPT_DIR/spawn-ticket-process.sh"

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
  --dry-run               Print the wave plan; do not spawn.
  --report <path>         Write the Markdown report to <path> (always also stdout).
EOF
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

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

run_wave() {
  local manifest="" concurrency=3 ram_thr=10 state_file="" poll_interval=10 spawn_helper="$DEFAULT_HELPER" dry=0 report=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest) manifest="$2"; shift 2 ;;
      --concurrency) concurrency="$2"; shift 2 ;;
      --ram-threshold) ram_thr="$2"; shift 2 ;;
      --state-file) state_file="$2"; shift 2 ;;
      --poll-interval) poll_interval="$2"; shift 2 ;;
      --spawn-helper) spawn_helper="$2"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --report) report="$2"; shift 2 ;;
      *) echo "usage error: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
    esac
  done

  [[ -n "$manifest" ]] || { echo "usage error: --manifest is required" >&2; usage >&2; exit 2; }
  [[ -f "$spawn_helper" ]] || { echo "error: spawn-helper not found: $spawn_helper" >&2; exit 1; }
  [[ "$concurrency" =~ ^[0-9]+$ && "$concurrency" -ge 1 ]] || { echo "error: --concurrency must be a positive int" >&2; exit 2; }

  local count
  parse_manifest "$manifest"
  count=$M_COUNT
  [[ "$count" -gt 0 ]] || { echo "manifest has 0 tickets" >&2; exit 1; }

  local _state_auto=0
  [[ -n "$state_file" ]] || { state_file=$(mktemp -t batch-wave-state.XXXXXX); _state_auto=1; }
  if [[ "$_state_auto" -eq 1 ]]; then
    # The wave created this temp file; clean it on exit so long unattended
    # runs don't leak across waves (tkt-242 L2). Single-quoted trap expands
    # at signal time; _WAVE_STATE_FILE is a shell global (not the run_wave
    # local) so it still holds the path when the trap fires at EXIT, after
    # run_wave has returned and the local is gone.
    _WAVE_STATE_FILE="$state_file"
    trap 'rm -f -- "$_WAVE_STATE_FILE"' EXIT
  fi

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
        STATUS[j]="workspace-failed"; continue
      fi
      local out
      if out=$(bash "$spawn_helper" --cwd "${M_WT[j]}" --brief-file "${M_BRIEF[j]}" --state-file "$state_file" 2>&1); then
        local pid
        pid=$(printf '%s\n' "$out" | sed -n 's/^spawned: pid=\([0-9]*\) .*/\1/p')
        [[ "$pid" =~ ^[0-9]+$ ]] || { STATUS[j]="workspace-failed"; echo "warn: spawn produced no pid for ${M_TICKET[j]}: $out" >&2; continue; }
        PIDS[j]="$pid"; STARTS[j]=$(now_epoch); STATUS[j]="running"
        # Grace-period re-check: an immediate-crash spawn (auth/OOM) would
        # otherwise be reported `completed` by the barrier's first poll —
        # indistinguishable from success mid-wave (tkt-242 L2). Probe again
        # after a short grace; a dead PID here is `spawned-but-dead`, not a
        # silent completed. Mirrors the spawn helper's own grace re-check.
        sleep "${SPAWN_GRACE_SEC:-0.3}"
        if bash "$spawn_helper" --probe "$pid" 2>/dev/null | grep -q "^alive:"; then
          echo "spawned: ${M_TICKET[j]} pid=$pid" >&2
        else
          STATUS[j]="spawned-but-dead"; ENDS[j]=$(now_epoch)
          echo "spawned-but-dead: ${M_TICKET[j]} pid=$pid (died within ${SPAWN_GRACE_SEC:-0.3}s grace)" >&2
        fi
      else
        STATUS[j]="workspace-failed"; echo "warn: spawn failed for ${M_TICKET[j]}: $out" >&2
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

  emit_report "$count" "$report"
}

# Poll all "running" tickets until none running. timebox per ticket (minutes).
barrier_poll() {
  local count="$1" interval="$2"
  while true; do
    local any_running=0
    for i in $(seq 0 $((count-1))); do
      [[ "${STATUS[i]}" == "running" ]] || continue
      any_running=1
      local pid="${PIDS[i]}"
      if bash "$spawn_helper" --probe "$pid" 2>/dev/null | grep -q "^alive:"; then
        # still alive — check timebox
        local elapsed=$(( $(now_epoch) - STARTS[i] ))
        local limit=$(( M_TIMEBOX[i] * 60 ))
        if [[ "$elapsed" -gt "$limit" ]]; then
          kill "$pid" 2>/dev/null || true
          STATUS[i]="timeout"; ENDS[i]=$(now_epoch)
          echo "timeout: ${M_TICKET[i]} pid=$pid (elapsed ${elapsed}s > timebox ${limit}s)" >&2
        fi
      else
        STATUS[i]="completed"; ENDS[i]=$(now_epoch)
        echo "completed: ${M_TICKET[i]} pid=$pid" >&2
      fi
    done
    [[ "$any_running" -eq 0 ]] && break
    sleep "$interval"
  done
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
  local completed=0 timeout=0 failed=0 spawned_dead=0
  for i in $(seq 0 $((count-1))); do
    local dur=0
    [[ "${ENDS[i]}" -gt 0 ]] && dur=$(( ENDS[i] - STARTS[i] ))
    lines+=("| ${M_TICKET[i]} | ${PIDS[i]:-—} | ${M_WT[i]} | ${STATUS[i]} | ${M_TIMEBOX[i]} | $dur |")
    case "${STATUS[i]}" in
      completed) completed=$((completed+1)) ;;
      timeout) timeout=$((timeout+1)) ;;
      spawned-but-dead) spawned_dead=$((spawned_dead+1)) ;;
      *) failed=$((failed+1)) ;;
    esac
  done
  lines+=("")
  lines+=("## Summary")
  lines+=("- spawned: $((count - failed - spawned_dead))")
  lines+=("- completed: $completed")
  lines+=("- timeout: $timeout")
  lines+=("- workspace-failed: $failed")
  lines+=("- spawned-but-dead: $spawned_dead")
  lines+=("")
  lines+=("Host: probe each completed ticket's PR via verify-mutation.sh (spawn-brief item 6).")
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

  # A fake spawn helper that spawns `sleep <timebox>min` surrogates so the wave
  # logic is exercised without real claude.
  local fake_helper sf
  fake_helper=$(mktemp -t bw-fakehelper.XXXXXX)
  sf=$(mktemp -t bw-fakestate.XXXXXX)
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
    # read timebox from brief file 3rd line? no — surrogate sleeps a fixed short time
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
    out=$(bash "$0" --manifest "$m" --spawn-helper "$fake_helper" --ram-threshold 0 --dry-run 2>/dev/null) || { rm -f "$m" "$brief" "$fake_helper"; rm -rf "$wt"; return 1; }
    rm -f "$m" "$brief"; rm -rf "$wt"
    [[ "$out" == *"dry-run: wave plan"* && "$out" == *"tkt-1"* ]]
  }
  chk "T3: --dry-run plan no-spawn" t3

  # T4: full wave — 2 sleep surrogates, all complete within timebox
  t4() {
    local m wt1 wt2 b1 b2 rep out
    m=$(mktemp -t bw-manifest.XXXXXX)
    wt1=$(mktemp -d -t bw-wt1.XXXXXX); wt2=$(mktemp -d -t bw-wt2.XXXXXX)
    b1=$(mktemp -t bw-b1.XXXXXX); echo x > "$b1"
    b2=$(mktemp -t bw-b2.XXXXXX); echo x > "$b2"
    rep=$(mktemp -t bw-rep.XXXXXX)
    printf 'tkt-A\t%s\t%s\t1\ntkt-B\t%s\t%s\t1\n' "$wt1" "$b1" "$wt2" "$b2" > "$m"
    out=$(bash "$0" --manifest "$m" --spawn-helper "$fake_helper" --ram-threshold 0 --state-file "$sf" --poll-interval 1 --concurrency 2 --report "$rep" 2>/dev/null) || { rm -f "$m" "$b1" "$b2" "$rep"; rm -rf "$wt1" "$wt2"; return 1; }
    local r=$?
    [[ "$out" == *"completed: 2"* ]] && [[ "$out" == *"tkt-A"* && "$out" == *"tkt-B"* ]]
    r=$?
    rm -f "$m" "$b1" "$b2" "$rep"; rm -rf "$wt1" "$wt2"
    return $r
  }
  chk "T4: wave spawn→poll→complete (2 surrogates)" t4

  # T5: timebox timeout — surrogate sleeps longer than timebox → killed+timeout
  #     (use a fake helper that sleeps 30s; timebox 1 min is too long for a test,
  #      so patch the helper to sleep 30 and set timebox 1 → but 1min>30s won't
  #      trip. Instead set timebox to 0 min → trips immediately.)
  t5() {
    # Build a slow fake helper (sleep 30)
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
    out=$(bash "$0" --manifest "$m" --spawn-helper "$slow_helper" --ram-threshold 0 --state-file "$sf" --poll-interval 1 --concurrency 1 --report "$rep" 2>/dev/null) || true
    rm -f "$m" "$b" "$rep" "$slow_helper"; rm -rf "$wt"
    [[ "$out" == *"timeout: 1"* ]]
  }
  chk "T5: timebox timeout → kill + timeout status" t5

  # T6: missing --manifest fails closed (exit 2)
  t6() { bash "$0" --spawn-helper "$fake_helper" >/dev/null 2>&1; [[ $? -eq 2 ]]; }
  chk "T6: missing --manifest fails closed" t6

  # T7: missing worktree → workspace-failed (not a hard crash)
  t7() {
    local m b rep out
    m=$(mktemp -t bw-manifest.XXXXXX)
    b=$(mktemp -t bw-b.XXXXXX); echo x > "$b"
    rep=$(mktemp -t bw-rep.XXXXXX)
    printf 'tkt-X\t/nonexistent/wt\t%s\t1\n' "$b" > "$m"
    out=$(bash "$0" --manifest "$m" --spawn-helper "$fake_helper" --ram-threshold 0 --state-file "$sf" --poll-interval 1 --report "$rep" 2>/dev/null) || true
    rm -f "$m" "$b" "$rep"
    [[ "$out" == *"workspace-failed: 1"* ]]
  }
  chk "T7: missing worktree → workspace-failed (not crash)" t7

  rm -f "$fake_helper" "$sf"
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
