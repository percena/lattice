# tkt-221-spawn-mode-flag-and-wiring

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** Add `--spawn-mode {agent,process}` (default `agent`) to `batch-work`; `process` mode calls the tkt-219 helper per ticket at SPAWN LAYER (worktree-bound) and polls `claude agents --json` + PID liveness at the barrier instead of the in-session completion channel; update SKILL.md + flow.md.
> **Kind:** feat · **Priority:** P1
> **Path:** spc-213 → tkt-221 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | enhancement, P1 |
| github | https://github.com/percena/lattice/issues/221 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-30T00:00:00Z |
| updated | 2026-08-30T17:10:00Z |
| adopted | false |
| summary | --spawn-mode {agent,process} flag + process SPAWN LAYER + PID/agents status detection + docs |
| spec | spc-213 — batch-work process-isolation spawn mode (path: ../../specs/spc-213-batch-work-process-spawn.md) |
| covers | A1, A3, A4, A5, A7, A8 |
| blocked_by | tkt-219 |
| parallel_group | (serial) |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-221 |
| **related_tickets** | tkt-219 |
| **worktree_bind** | tkt-221-spawn-mode-flag-and-wiring |
| worktree | sibling `…/lattice.worktrees/tkt-221-spawn-mode-flag-and-wiring/` |
| prs | (none) |

## Acceptance (this slice)

- [x] **A1** — `--spawn-mode {agent,process}` parsed in INTAKE; default `agent`; unknown value fails closed with usage. `--dry-run` prints `spawn-mode: <mode>` in the report header.
- [x] **A3** — `process` mode SPAWN LAYER calls `spawn-ticket-process.sh` (tkt-219) per ticket, bound to the ticket's sibling worktree via `ensure-workspace --mode worktree --bind tkt`; capped by `--concurrency` per wave, RAM-gated before each wave; host records PID + spawn timestamp (watchdog input).
- [x] **A4** — `process` mode LAYER/WAVE BARRIER polls `claude agents --json` + `process.kill(pid, 0)` to classify each ticket `ok`/`failed`/`timeout` (watchdog timebox still enforced on the recorded spawn timestamp), instead of the in-session background-completion channel. `agent` mode keeps the in-session channel unchanged.
- [x] **A5** — All orchestration invariants hold identically in both modes: independence gate, worktree-per-tkt, `.batch-work-active` merge marker (written before first spawn in both modes), fuse + graceful drain, spawn-brief contract (all six items ride the `process`-mode `-p` prompt / brief-file), stacked dependency bases, binder SoT stamping.
- [x] **A7** — SKILL.md + `references/flow.md` document `--spawn-mode`, the `process`-mode SPAWN LAYER recipe, the polling status-detection recipe, the cross-mode invariant clause, and the verification checklist item ("spawn-mode selection honored at SPAWN LAYER").
- [x] **A8** — No regression: `agent` mode behavior unchanged end-to-end; `--dry-run --ids ...` output identical except the added `spawn-mode:` line; existing callers omitting the flag get `agent` mode.

## Approach

- INTAKE (`SKILL.md` Flow step 1): parse `--spawn-mode`, validate ∈ {agent,process}, default agent; thread into dry-run header + spawn/collect.
- SPAWN LAYER (`flow.md` §SPAWN LAYER): branch on mode; `process` mode → ensure-workspace worktree, then call `bash skills/batch-work/scripts/spawn-ticket-process.sh --cwd <wt> --brief-file <path> --state-file <batch-state>`; record PID + spawn timestamp per ticket. `agent` mode → existing Task path unchanged.
- LAYER BARRIER (`flow.md` §LAYER BARRIER): `process` mode → poll `claude agents --json` + `kill -0 <pid>` per ticket until all settled or watchdog timebox trips; classify ok/failed/timeout. `agent` mode → existing background-completion channel.
- `flow.md` new sections: §PROCESS-MODE SPAWN, §PROCESS-MODE STATUS DETECTION.
- `SKILL.md`: `--spawn-mode` in argument-hint + Defaults table; cross-mode invariant clause in Invariants; verification checklist row.

## Anticipated decisions

- spawn-brief rides `-p` prompt / brief-file in process mode (D4) — pre-resolved (ADR-008); brief must carry all six contract items.
- process mode is headless (D5) — pre-resolved (ADR-008); no tmux/Terminal wrapping.
- host stays coordinator (D3) — pre-resolved (ADR-008); stateless coordinator is out of scope.

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

<!-- none yet -->

## Attempts

<!-- Fallback ledger, one entry per attempt. -->

## Notes

- Path-disjoint from tkt-219 (this touches SKILL.md + flow.md; tkt-219 touches scripts/), but serial because the wiring depends on the helper existing.
- `blocked_by: tkt-219` — do not start until tkt-219's helper lands (or co-develop against the helper's agreed interface).

## References

- GitHub issue body is SoT for long prose: #221
- Spec: `spc-213` (path above)
- ADR: `ADR-008` → `docs/adr/008-batch-work-process-isolation-spawn.md`
- Worktree policy: one tree ↔ one PR

## Lineage

- Parent spec: **spc-213**
- Parent issue (GH sub-issue of Spec primary): **#218**
- Primary ticket: **tkt-221**
