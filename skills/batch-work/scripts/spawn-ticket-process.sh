#!/usr/bin/env bash
# spawn-ticket-process.sh — spawn an independent `claude --bg` process per
# ticket worktree, record its PID + worktree + start time to a per-batch state
# file, and provide a PID-liveness probe for the orchestrator's barrier loop.
#
# This is the `--spawn-mode process` execution primitive for batch-work
# (ADR-008, spc-213). It borrows a reference batch tool's detached-process +
# PID/agents-polling pattern and fixes that tool's shared-cwd defect by making
# `--cwd` a required argument bound to the ticket's sibling worktree
# (ADR-006 worktree isolation preserved).
#
# Why a process, not an in-session Task subagent: the Task tool spawns children
# of the host LLM session — (1) N completion reports flood the host context and
# degrade fuse/watchdog/report reasoning at scale; (2) a host-process crash
# kills the entire batch. An independent `claude --bg` detached process has
# true process-level failure isolation and frees the host context. The host
# stays the coordinator (ADR-008 D3); this helper owns only spawn + state.
#
# Usage:
#   spawn-ticket-process.sh --cwd <worktree> --brief-file <path>
#       [--state-file <path>] [--permission-mode acceptEdits]
#       [--base <ref>] [--repo <owner/name>] [--dry-spawn]
#   spawn-ticket-process.sh --probe <pid>           # liveness check (ground truth: kill -0)
#   spawn-ticket-process.sh --self-test
#   spawn-ticket-process.sh --help
#
# Exit codes:
#   0  spawn: spawned + recorded (prints "spawned: pid=<pid> worktree=<path>")
#      probe: prints "alive: <pid>" or "dead: <pid>" and exits 0 either way
#      self-test: all assertions passed (prints PASS/FAIL lines)
#   1  spawn failed / self-test assertion failed / probe of a non-numeric pid
#   2  usage error (missing required flag)
#
# bash 3.2 portable (no mapfile; [[ ]] used; `kill -0` is the portable liveness
# ground truth — `claude agents --json` is enrichment, never the sole signal).

set -euo pipefail

usage() {
  cat <<EOF
usage: spawn-ticket-process.sh --cwd <worktree> --brief-file <path>
       [--state-file <path>] [--permission-mode acceptEdits]
       [--base <ref>] [--repo <owner/name>] [--dry-spawn]
       spawn-ticket-process.sh --probe <pid>
       spawn-ticket-process.sh --self-test
       spawn-ticket-process.sh --help

  --cwd <worktree>       Required. Working directory for the spawned agent
                         (the ticket's sibling worktree — fixes the reference
                         tool's shared-cwd defect; ADR-006 isolation preserved).
  --brief-file <path>    Required. File whose contents become the -p prompt.
                         Must carry all six spawn-brief contract items
                         (ADR-008 D4); the orchestrator assembles it.
  --state-file <path>    Per-batch state file. Appends a TSV record:
                         pid<TAB>worktree<TAB>started_iso. Default: a temp file
                         path is printed to stdout for the caller.
  --permission-mode      Passed to claude (default: acceptEdits).
  --base <ref>           Recorded in state for traceability (not passed to
                         claude; the worktree already branched off this base).
  --repo <owner/name>    Recorded in state for traceability.
  --dry-spawn            Validate args + assemble the command; do NOT spawn.
                         Prints the would-be command. Exits 0.

  --probe <pid>          Liveness probe. Ground truth: \`kill -0 <pid>\`.
                         Prints "alive: <pid>" or "dead: <pid>"; exits 0.
  --self-test            Exercise PID tracking + liveness against a dummy
                         surrogate (sleep) without launching real work.
EOF
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# kill -0 is the portable liveness ground truth across macOS/Linux.
# Returns 0 if alive, 1 if dead/owned-by-other, non-numeric handled by caller.
is_alive() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

# Enrichment only: best-effort read of `claude agents --json` to confirm the
# PID appears as a known background agent. Tolerates schema drift / CLI absence
# by falling back to the kill -0 ground truth (returned via stdout "yes"/"no",
# empty string on any failure — caller treats empty as "unknown, trust kill -0").
agent_known() {
  local pid="$1"
  command -v claude >/dev/null 2>&1 || { echo ""; return 0; }
  local out
  out=$(claude agents --json 2>/dev/null || true)
  [[ -n "$out" ]] || { echo ""; return 0; }
  # Match the pid anywhere in the JSON blob (schema-agnostic) — enrichment.
  if printf '%s' "$out" | grep -q "\"$pid\""; then echo "yes"; else echo "no"; fi
}

# Append a TSV state record: pid<TAB>worktree<TAB>started_iso[<TAB>base,repo]
record_state() {
  local state_file="$1" pid="$2" worktree="$3" started="$4" base="${5:-}" repo="${6:-}"
  local dir
  dir=$(dirname "$state_file")
  [[ -d "$dir" ]] || mkdir -p "$dir"
  printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$worktree" "$started" "$base" "$repo" >> "$state_file"
}

# ---------------------------------------------------------------------------
# spawn
# ---------------------------------------------------------------------------

do_spawn() {
  local cwd="" brief_file="" state_file="" pm="acceptEdits" base="" repo="" dry=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd) cwd="$2"; shift 2 ;;
      --brief-file) brief_file="$2"; shift 2 ;;
      --state-file) state_file="$2"; shift 2 ;;
      --permission-mode) pm="$2"; shift 2 ;;
      --base) base="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      --dry-spawn) dry=1; shift ;;
      *) echo "usage error: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
    esac
  done

  [[ -n "$cwd" ]] || { echo "usage error: --cwd is required" >&2; usage >&2; exit 2; }
  [[ -n "$brief_file" ]] || { echo "usage error: --brief-file is required" >&2; usage >&2; exit 2; }
  [[ -d "$cwd" ]] || { echo "error: --cwd does not exist: $cwd" >&2; exit 1; }
  [[ -f "$brief_file" ]] || { echo "error: --brief-file does not exist: $brief_file" >&2; exit 1; }

  [[ -n "$state_file" ]] || state_file=$(mktemp -t batch-work-state.XXXXXX)

  local prompt
  prompt=$(cat "$brief_file")

  # Assemble the claude --bg command. --bg starts the session as a background
  # agent (detached from the caller's TTY). We do NOT stdio-ignore here so a
  # misconfigured spawn surfaces; the orchestrator may redirect if it wants.
  local cmd_args=(claude --bg -p "$prompt" --permission-mode "$pm")
  if [[ -n "$dry" ]]; then
    echo "dry-spawn: would run: ${cmd_args[*]} (cwd=$cwd)"
    echo "dry-spawn: state-file=$state_file"
    exit 0
  fi

  # Spawn detached. `exec` inside a subshell that is itself backgrounded makes
  # `$!` the spawned process's PID (the subshell replaces itself). `disown`
  # detaches it from this shell's job table so the host's exit won't reap it.
  local started pid
  started=$(now_iso)
  ( cd "$cwd" && exec env BATCH_TICKET=1 BATCH_BASE="$base" BATCH_REPO="$repo" \
      nohup "${cmd_args[@]}" >/dev/null 2>&1 ) &
  pid=$!
  disown "$pid" 2>/dev/null || true
  # The subshell's `$!` is the nohup'd claude PID on bash. Verify it is alive
  # before recording (catches a failed-to-start spawn, e.g. missing claude).
  if ! is_alive "$pid"; then
    echo "FAILED: spawn did not produce a live process (pid=$pid); is 'claude' on PATH?" >&2
    exit 1
  fi

  record_state "$state_file" "$pid" "$cwd" "$started" "$base" "$repo"
  echo "spawned: pid=$pid worktree=$cwd"
  echo "state-file=$state_file"
}

# ---------------------------------------------------------------------------
# probe
# ---------------------------------------------------------------------------

do_probe() {
  local pid=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --probe) pid="$2"; shift 2 ;;
      *) echo "usage error: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  [[ "$pid" =~ ^[0-9]+$ ]] || { echo "usage error: --probe needs a numeric pid" >&2; exit 1; }
  if is_alive "$pid"; then
    echo "alive: $pid"
  else
    echo "dead: $pid"
  fi
  exit 0
}

# ---------------------------------------------------------------------------
# self-test (exercises PID tracking + liveness against a dummy surrogate)
# ---------------------------------------------------------------------------

self_test() {
  local fail=0
  # Usage: chk "<label>" <func> [args...]
  chk() {
    local label="$1"; shift
    if "$@"; then echo "PASS: $label"; else echo "FAIL: $label"; fail=$((fail+1)); fi
  }

  # T1: is_alive detects a live sleep surrogate
  t1() {
    sleep 5 & local p=$!
    is_alive "$p"; local r=$?
    kill "$p" 2>/dev/null || true
    return $r
  }
  chk "T1: is_alive live surrogate" t1

  # T2: is_alive returns false for a dead pid
  t2() {
    local p
    p=$(sleep 1 & echo $!)
    wait "$p" 2>/dev/null || true
    # ensure dead
    sleep 2
    if is_alive "$p"; then return 1; else return 0; fi
  }
  chk "T2: is_alive dead pid" t2

  # T3: is_alive rejects non-numeric
  t3() { if is_alive "not-a-pid"; then return 1; else return 0; fi; }
  chk "T3: is_alive non-numeric reject" t3

  # T4: record_state writes a TSV line + reads back
  t4() {
    local sf
    sf=$(mktemp -t bw-selftest.XXXXXX)
    record_state "$sf" "4242" "/tmp/wt" "2026-01-01T00:00:00Z" "dev" "percena/lattice"
    local line
    line=$(cat "$sf")
    [[ "$line" == $'4242\t/tmp/wt\t2026-01-01T00:00:00Z\tdev\tpercena/lattice' ]]
    local r=$?
    rm -f "$sf"
    return $r
  }
  chk "T4: record_state TSV shape" t4

  # T5: full spawn→record→probe→kill→probe cycle with a sleep surrogate via a
  #     tmp "brief" (we don't launch real claude in self-test; we exercise the
  #     spawn+record+probe path by substituting `sleep` through a wrapper).
  t5() {
    local sf cwd brief
    sf=$(mktemp -t bw-selftest.XXXXXX)
    cwd=$(mktemp -d -t bw-wt.XXXXXX)
    brief=$(mktemp -t bw-brief.XXXXXX)
    echo "dummy brief" > "$brief"
    # Monkey-spawn: emulate do_spawn's record + a sleep surrogate in place of
    # claude, to exercise record_state + is_alive without a real claude launch.
    local started p
    started=$(now_iso)
    ( cd "$cwd" && exec nohup sleep 5 >/dev/null 2>&1 ) &
    p=$!
    disown "$p" 2>/dev/null || true
    record_state "$sf" "$p" "$cwd" "$started" "" ""
    is_alive "$p" || { rm -rf "$cwd" "$brief" "$sf"; return 1; }
    kill "$p" 2>/dev/null || true
    sleep 1
    if is_alive "$p"; then rm -rf "$cwd" "$brief" "$sf"; return 1; fi
    rm -rf "$cwd" "$brief" "$sf"
    return 0
  }
  chk "T5: spawn→record→probe→kill→probe cycle" t5

  # T6: --dry-spawn validates args + assembles command without spawning
  t6() {
    local out cwd brief
    cwd=$(mktemp -d -t bw-wt.XXXXXX)
    brief=$(mktemp -t bw-brief.XXXXXX)
    echo "x" > "$brief"
    out=$(bash "$0" --cwd "$cwd" --brief-file "$brief" --dry-spawn 2>/dev/null) || { rm -rf "$cwd" "$brief"; return 1; }
    rm -rf "$cwd" "$brief"
    [[ "$out" == *"dry-spawn: would run:"* && "$out" == *"state-file="* ]]
  }
  chk "T6: --dry-spawn no-spawn assemble" t6

  # T7: missing --cwd fails closed (exit 2)
  t7() {
    local brief
    brief=$(mktemp -t bw-brief.XXXXXX)
    echo "x" > "$brief"
    bash "$0" --brief-file "$brief" >/dev/null 2>&1; local r=$?
    rm -f "$brief"
    [[ $r -eq 2 ]]
  }
  chk "T7: missing --cwd fails closed" t7

  # T8: missing --brief-file fails closed (exit 2)
  t8() {
    local cwd
    cwd=$(mktemp -d -t bw-wt.XXXXXX)
    bash "$0" --cwd "$cwd" >/dev/null 2>&1; local r=$?
    rm -rf "$cwd"
    [[ $r -eq 2 ]]
  }
  chk "T8: missing --brief-file fails closed" t8

  echo ""
  if [[ $fail -eq 0 ]]; then
    echo "✅ spawn-ticket-process.sh --self-test passed"
  else
    echo "❌ spawn-ticket-process.sh --self-test FAILED ($fail failure(s))"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage; exit 0
  fi
  case "${1:-}" in
    --probe) do_probe "$@" ;;
    --self-test) self_test ;;
    *) do_spawn "$@" ;;
  esac
}

main "$@"
