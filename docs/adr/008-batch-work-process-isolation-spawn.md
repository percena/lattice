# ADR 008: Batch-work process-isolation spawn mode

- **Status:** Accepted
- **Date:** 2026-08-30
- **Deciders:** maintainers
- **Related:** `spc-213`, ERP `tools/batch-implement.mjs` (reference), `skills/batch-work`
- **Related ADRs:** `ADR-004` (attention contract / night-shift delivery — the fuse + graceful-drain law this builds on), `ADR-005` (version bump at release boundary — the stacked-base contract this preserves), `ADR-006` (worktree discipline — the sibling-tree isolation this keeps)

## Context

`batch-work` today spawns one `Task` (`subagent_type: general-purpose`, `run_in_background: true`) per ticket. The Task tool is Claude Code's in-session subagent primitive: each spawned agent is a child of **the host LLM session** that runs the skill, not an independent OS process. Two structural costs follow, and both hit execution quality — not human visibility, which is irrelevant here:

1. **The coordinator is the host LLM session.** DAG build, spawn, barrier-wait, watchdog, fuse computation, binder stamping, and report generation all run in the *same context window* that also receives every spawned agent's completion notification. As the batch grows, N completion reports flood the host context, degrading the host's reasoning over spawn rhythm, fuse calls, and the report. The orchestrator and the workers share one cognitive container.
2. **Host-crash blast radius.** All in-session Task subagents are children of the host process. If the host OOMs or crashes, the entire batch dies simultaneously — even though each subagent nominally has its own context window. Failure isolation covers per-agent crashes, not host-process death.

ERP's `batch-implement.mjs` (the reference the user pointed to) takes the inverse shape: the coordinator is a **stateless node process** with zero LLM context, and each ticket runs as an independent `claude --bg` detached + `unref()` OS process. Status is polled via `claude agents --json` + `process.kill(pid, 0)`, not via an in-session completion channel. `claude --bg` and `claude agents` are confirmed available on this CLI (v2.1.246), so the primitive ports.

ERP's编排 layer is, however, far weaker than Lattice's: all agents share one `cwd` (no worktree isolation), no independence gate, no fuse, no spawn-brief contract, no batch merge marker, no stacked-base handling, coarse per-layer timeout. Lattice already solved all of those. The valuable part of ERP is **only the execution primitive and the stateless-coordinator shape**, not its orchestration.

## Decision Drivers

- **Execution isolation over visibility.** The user's stated goal is execution quality: agents distributed across independent processes/sessions perform better than agents crammed into one session/host. Human-visible terminals are not a requirement.
- **Host context must not be the bottleneck.** A batch of 6+ tickets must not degrade the coordinator's reasoning because completion reports fill its context.
- **No regression to Lattice's orchestration invariants.** Independence gate, one-worktree-per-tkt, batch merge marker, fuse + graceful drain, spawn-brief contract, stacked dependency bases, binder SoT stamping — all must survive the change.
- **Backward compatibility.** Existing `batch-work` callers that rely on the in-session Task path must not break on day one.

## Considered Options

- **Option A — Replace Task with `claude --bg` process spawn (ERP-style), stateless coordinator.** Good: true process isolation, host context freed, host-crash blast radius eliminated. Bad: loses the in-session completion channel (must switch to PID/`claude agents` polling); a stateless node coordinator means the skill's reasoning moves partly out of the LLM into a script.
- **Option B — Keep Task, add a context-spill drain.** Good: minimal change. Bad: cannot fix host-crash blast radius or host-context flooding; the root cause is structural, not a drain away.
- **Option C — Hybrid: `--spawn-mode {agent,process}`, default `agent`, opt-in `process`.** Good: backward compatible; lets the user opt into process isolation where execution quality matters; both paths share the orchestration layer. Bad: two code paths to maintain; the process path needs its own status-detection backend.

## Decision

We will adopt **Option C** — add a `--spawn-mode {agent,process}` flag to `batch-work`, keeping `agent` (in-session Task subagent) as the backward-compatible default and adding `process` as the execution-isolation mode. In `process` mode:

- SPAWN LAYER spawns each ticket as an independent `claude --bg` detached process (`stdio` configurable) whose `cwd` is the ticket's sibling worktree (preserving ADR-006 worktree isolation — this is the ERP hard- defect fixed).
- The spawn is mediated by a thin helper script (`skills/batch-work/scripts/spawn-ticket-process.sh` or `.mjs`) so the host LLM session never directly holds N child PIDs in-band; the script records spawn timestamp + PID + worktree path for the watchdog.
- Status detection switches from the in-session background-completion channel to `claude agents --json` + PID liveness polling (the ERP pattern), driven by the host's barrier loop.
- The coordinator remains the host LLM session for DAG/gate/fuse/binder/marker/report reasoning, but its context is no longer flooded by per-agent completion reports — those land in the helper script's state file, and the host reads a compact summary at each barrier. (A fully stateless node coordinator is a possible later phase; this Spec keeps the host-as-coordinator shape and isolates the win that matters: spawn + status.)

Everything else — DAG build, independence gate, layer/wave barrier, watchdog timebox, fuse + graceful drain, `.batch-work-active` merge marker, spawn-brief contract, stacked dependency bases, binder SoT stamping, report — is unchanged across both modes.

**INVARIANT:** worktree-per-tkt, independence gate, batch marker, fuse, and spawn-brief contract hold in **both** modes. The mode flag only selects the execution primitive and the status-detection backend.

## Consequences

- **Positive:**
  - `process` mode gives true process-level failure isolation: a host crash no longer kills the batch; one agent's process death is invisible to peers.
  - Host LLM context is freed from N completion reports → reasoning over fuse/watchdog/report stays sharp at scale.
  - Each agent is a fully independent `claude` process with its own context budget and connection — no host-process coupling.
  - ERP's `claude agents --json` + PID liveness pattern is proven and ports directly.
- **Negative / trade-offs:**
  - Two spawn/status code paths (`agent` vs `process`) — the process path needs its own polling loop and a spawn helper script.
  - `process` mode spawns real `claude` processes → heavier per-agent resource footprint than in-session subagents; the RAM gate (already present) is the bound, and `--concurrency` already caps the wave.
  - The spawn-brief must be passed to `claude --bg` via `-p` (prompt string) or a brief file — the brief contract items must all ride that prompt, not rely on in-session context.
- **Follow-ups:** `spc-213` (the feature Spec) and its tickets carry the implementation. `ADR-004` fuse law and `ADR-006` worktree law are preserved, not amended.
- **Verification:** `--dry-run` prints the spawn mode in the DAG report; `--self-test` (borrowed from ERP's pattern) exercises the spawn helper's PID tracking and status polling without launching real agents; the verification checklist gains a "spawn-mode selection honored at SPAWN LAYER" item.

## Status history

- 2026-08-30: Proposed
- 2026-08-30: Proposed → Accepted (implemented via spc-213: tkt-219 PR#225 + tkt-221 PR#228)

## Notes

Rejected: Option B (context-spill drain) — cannot fix the structural host-crash blast radius; the root cause is the in-session child model, not report size. A future phase may make the coordinator fully stateless (node-only, no LLM session) per ERP's shape; this ADR scopes the win to spawn + status isolation and leaves the coordinator shape intact so the change is reviewable in one Spec.

ERP reference value is **only** the execution primitive (`cpSpawn('claude', ['--bg', ...], {detached, stdio, env}) + child.unref()`) and the status-detection pattern (`claude agents --json` + `process.kill(pid, 0)`). ERP's shared-`cwd` defect is explicitly NOT borrowed — Lattice's per-ticket worktree binds the `cwd`.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-008` or this path._
