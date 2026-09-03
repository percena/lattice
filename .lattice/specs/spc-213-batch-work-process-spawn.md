---
# status: draft | locked | done | superseded
id: spc-213
slug: batch-work-process-spawn
title: Batch-work process-isolation spawn mode (--spawn-mode process)
kind: feat
status: done
mode: C
priority: P1
summary: "Add --spawn-mode {agent,process} to batch-work; process mode spawns independent claude --bg per worktree + PID/agents polling, freeing host context and isolating host-crash blast radius"
created: 2026-08-30
updated: 2026-08-30
tickets: [tkt-219, tkt-221]
prs: [pr-225, pr-228]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Batch-work process-isolation spawn mode (`--spawn-mode process`)

> **TL;DR:** Add a `--spawn-mode {agent,process}` flag to `batch-work`. `process` mode spawns each ticket as an independent `claude --bg` detached process in its own worktree and detects completion via `claude agents --json` + PID liveness polling — freeing the host LLM context from N completion reports and eliminating host-crash blast radius. `agent` mode (current in-session Task subagent) stays the backward-compatible default. All orchestration invariants (independence gate, worktree-per-tkt, batch marker, fuse, spawn-brief contract, stacked bases, binder SoT) hold in both modes.
> **Kind:** feat · **Status:** done · **Mode:** C · **Priority:** P1
> **Path:** spc-213 → tkt-… → pr-…

## Why

`batch-work` spawns one `Task` (`subagent_type: general-purpose`, `run_in_background: true`) per ticket. The Task tool is Claude Code's **in-session** subagent primitive: each agent is a child of the host LLM session, not an independent OS process. Two structural costs hit execution quality (visibility is irrelevant — the user's goal is execution isolation):

1. **Coordinator is the host LLM session.** DAG build, spawn, barrier-wait, watchdog, fuse, binder stamping, and report all run in the *same context window* that receives every spawned agent's completion notification. As the batch grows, N completion reports flood the host context, degrading reasoning over spawn rhythm, fuse calls, and the report. Orchestrator and workers share one cognitive container.
2. **Host-crash blast radius.** All in-session Task subagents are children of the host process. If the host OOMs or crashes, the entire batch dies simultaneously, even though each subagent nominally has its own context window. Failure isolation covers per-agent crashes, not host-process death.

ERP's `batch-implement.mjs` (the reference) takes the inverse shape: a **stateless node** coordinator with zero LLM context, each ticket an independent `claude --bg` detached + `unref()` OS process, status polled via `claude agents --json` + `process.kill(pid, 0)`. `claude --bg` and `claude agents` are confirmed on this CLI (v2.1.246). ERP's orchestration layer is weaker (shared `cwd`, no gate/fuse/brief/marker) — Lattice already solved all of that. The borrow is **only** the execution primitive + status-detection pattern, with the shared-`cwd` defect fixed by binding `cwd` to each ticket's worktree.

## In scope

- New `--spawn-mode {agent,process}` flag (default `agent`) parsed in INTAKE and threaded through SPAWN LAYER + status detection.
- New spawn helper script `skills/batch-work/scripts/spawn-ticket-process.sh` (bash) that spawns `claude --bg -p "<brief>" --permission-mode acceptEdits` detached in a given worktree `cwd`, records PID + worktree + spawn timestamp to a per-batch state file, and returns the PID. Borrows ERP's `cpSpawn(detached, unref)` shape; fixes ERP's shared-`cwd` defect by taking `--cwd <worktree>`.
- New status-detection backend for `process` mode: poll `claude agents --json` + `process.kill(pid, 0)` liveness at the LAYER/WAVE BARRIER, driven by the host's barrier loop (watchdog timebox still enforced on the recorded spawn timestamp).
- `--dry-run` prints the selected spawn mode in the DAG report line.
- `--self-test` for the spawn helper (borrowing ERP's self-test pattern): exercises PID tracking + liveness probe against a dummy `claude --bg` echo without launching real implementation work.
- SKILL.md + `references/flow.md` updates: document `--spawn-mode`, the `process`-mode SPAWN LAYER recipe, the polling status-detection recipe, the invariant that both modes share all orchestration gates, and the verification checklist addition.
- `.lattice/config.yaml` doc: note the new flag (no new tunable required; `--concurrency` already bounds the wave).

## Out of scope

- Making the coordinator fully stateless (node-only, no LLM session). This ADR/Spec scopes the win to spawn + status isolation and leaves the host-as-coordinator shape intact so the change is reviewable in one Spec. A future phase may make the coordinator stateless.
- Replacing the `agent` (Task) mode or removing it. It remains the default for backward compatibility.
- New tunables beyond `--spawn-mode`. `--concurrency`, RAM threshold, timebox, and fuse threshold already bound `process` mode.
- Changing the spawn-brief contract — all six items ride the `-p` prompt string in `process` mode exactly as they ride the Task brief in `agent` mode.
- Spawning visible terminals (tmux/Terminal.app). Visibility is not a goal; `process` mode is headless (`stdio` configurable to `pipe`/`ignore`).

## Non-goals

- We will not diverge orchestration invariants by mode: independence gate, worktree-per-tkt, `.batch-work-active` marker, fuse + graceful drain, spawn-brief contract, stacked dependency bases, binder SoT stamping are INVARIANT across both modes.
- We will not have `process` mode bypass the RAM gate or concurrency cap — `process` agents are heavier (real `claude` processes) so the existing gates are more important, not less.

## Acceptance

- [x] **A1** — `--spawn-mode {agent,process}` flag parsed in INTAKE; default `agent`; unknown value fails closed with usage. `--dry-run` prints `spawn-mode: <mode>` in the report.
- [x] **A2** — `skills/batch-work/scripts/spawn-ticket-process.sh` exists; `--cwd <worktree> --brief-file <path> [--base <ref>]` spawns `claude --bg` detached with `BATCH_IMPLEMENT=1`-equivalent env, records `pid`, `worktree`, `started` (UTC ISO) to a given state file, exits 0 on spawn. Missing `--cwd` or `--brief-file` → fail closed.
- [x] **A3** — In `process` mode, SPAWN LAYER calls the helper per ticket (capped by `--concurrency` per wave, RAM-gated before each wave), bound to the ticket's sibling worktree via `ensure-workspace --mode worktree --bind tkt` (worktree isolation preserved); the host records the PID + spawn timestamp.
- [x] **A4** — In `process` mode, LAYER/WAVE BARRIER polls `claude agents --json` + `process.kill(pid, 0)` to classify each ticket `ok`/`failed`/`timeout` (watchdog timebox still enforced on the recorded spawn timestamp), instead of the in-session background-completion channel. `agent` mode keeps the in-session channel unchanged.
- [x] **A5** — All orchestration invariants hold identically in both modes: independence gate, worktree-per-tkt, `.batch-work-active` merge marker (written before first spawn in both modes), fuse + graceful drain, spawn-brief contract (all six items ride the `process`-mode `-p` prompt), stacked dependency bases, binder SoT stamping.
- [x] **A6** — `--self-test` exercises the spawn helper's PID tracking + liveness probe against a dummy (e.g. `claude --bg -p "echo ready"` or a `sleep` surrogate) without launching real implementation; asserts PID recorded + liveness detected + liveness-false after kill.
- [x] **A7** — SKILL.md + `references/flow.md` document `--spawn-mode`, the `process`-mode SPAWN LAYER recipe, the polling status-detection recipe, the cross-mode invariant clause, and the verification checklist item ("spawn-mode selection honored at SPAWN LAYER").
- [x] **A8** — No regression: `agent` mode behavior unchanged end-to-end; `--dry-run --ids ...` output identical except for the added `spawn-mode:` line; existing batch-work callers that omit the flag get `agent` mode.

## Decisions (principal, user-confirmed)

1. **D1 — Hybrid, not replace (Option C).** `--spawn-mode {agent,process}`, default `agent`, opt-in `process`. Backward compatible; the user opts into process isolation where execution quality matters. Both paths share the orchestration layer. (ADR-008 §Decision.)
2. **D2 — Borrow ERP's execution primitive + status pattern only; fix its shared-`cwd` defect.** `cpSpawn('claude', ['--bg', ...], {detached, unref})` + `claude agents --json` + `process.kill(pid, 0)`. Bind `cwd` to the ticket's worktree via `ensure-workspace` so ERP's shared-checkout defect is not inherited.
3. **D3 — Host stays the coordinator.** This Spec does not make the coordinator stateless node; it keeps the host LLM session as DAG/gate/fuse/marker/report owner and isolates the win to spawn + status (completion reports land in the helper's state file, host reads a compact summary at the barrier). A fully stateless coordinator is a possible later phase, out of scope here.
4. **D4 — Spawn-brief rides the `-p` prompt in `process` mode.** All six Spawn-brief contract items must be materialized into the prompt string (or a brief file the agent reads), not rely on in-session context. A brief missing any applicable item is malformed and must not spawn — same rule as `agent` mode.
5. **D5 — `process` mode is headless.** Visibility is not a goal. `stdio` is configurable (`ignore` default, `pipe` for diagnostics) — no tmux/Terminal.app wrapping in this Spec.

## Agent-assumed (secondary)

- The spawn helper may be `.sh` (bash, consistent with `_lattice-lib/scripts`) — no need for a `.mjs`; ERP's `.mjs` shape is reference, not a port requirement.
- `claude agents --json` output schema is taken as-is from the CLI; the helper tolerates schema drift by falling back to `process.kill(pid, 0)` liveness alone.

## Risks / open questions

- `claude --bg`'s exact `-p` prompt length limits vs. the full spawn-brief — if the brief is too long for `-p`, the brief-file approach (agent reads a file in-worktree) is the fallback; resolve during tkt implementation.
- `claude agents --json` schema stability across CLI versions — mitigate by treating PID liveness as the ground truth and `agents --json` as enrichment.
- Whether `process`-mode `claude --bg` honors `--permission-mode acceptEdits` identically to in-session — verify in tkt; ERP uses it so precedent exists.

## References

- ADR: `ADR-008` → `docs/adr/008-batch-work-process-isolation-spawn.md`
- Reference: ERP `tools/batch-implement.mjs` (cross-repo, not vendored — pattern only)
- Prior Spec: none (new capability)
- Issue: (to be filed by `create-tickets`)

## Links / bloodline (L0)

- Tickets: (to be split by `create-tickets`)
- PRs: prefer GitHub `Fixes`/`Refs`; Spec.prs is recovery
- Reviews: (none yet)
