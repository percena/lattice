# tkt-273 — Deterministic process proof and binder fail-close

> **TL;DR:** Correlate bounded worker probes with result artifacts and atomically fail-close every non-ok process node.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-270 → tkt-273 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/273 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-09-01T09:53:18Z |
| adopted | false |
| summary | Deterministically classify process workers and atomically stamp failed/timeout/unknown binders stuck. |
| spec | spc-270 — workflow proof closure follow-up (path: ../../specs/spc-270-workflow-proof-closure-followup.md) |
| covers | A2 |
| blocked_by | #271 |
| merge_blocked_by | #271 |
| parallel_group | proof-wave-1 |
| paths | skills/batch-work/scripts/run-process-wave.sh, skills/batch-work/scripts/spawn-ticket-process.sh, skills/batch-work/scripts/tests/**, skills/batch-work/references/flow.md, skills/batch-work/SKILL.md |
| solo_merge | yes |
| **primary_ticket** | tkt-273 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-273-deterministic-process-proof` |
| worktree | sibling `…/lattice.worktrees/tkt-273-deterministic-process-proof/` |
| prs | pr-316 — https://github.com/percena/lattice/pull/316 |

## Acceptance (this slice)

- [x] **A2.1** Worker result artifacts plus bounded PID/session-correlated probes classify only `ok|failed|timeout|unknown`; PID disappearance alone is never success. *(bounded PID probe via PROBE_TIMEOUT_SEC; PID↔session correlation deferred per spc-270 A2 — uncorrelated agents output is advisory, never a hard veto (A2.4).)*
- [x] **A2.2** `failed|timeout|unknown` atomically transition the real binder to `stuck + wait_reason: unblock` through tkt-271's API.
- [x] **A2.3** Transition failure prevents node settle and makes wave output/exit status machine-decidably non-ok.
- [x] **A2.4** Global unrelated agent failures cannot contaminate the ticket's classification.
- [x] **A2.5** Crash, hang, no-PR, missing/malformed result, and global-agent-noise fault tests terminate within bounded time.

## Approach

Make the result artifact the primary ticket-scoped completion signal and treat `claude agents --json` only as bounded, correlated enrichment. Add explicit probe timeouts and ticket/PID/session matching. Route every non-ok terminal classification through the atomic transition API delivered by tkt-271; if that mutation fails, retain a non-settled error state and return nonzero. Keep coordinator internals out of this slice so tkt-275 can consume a stable process result contract later.

## Anticipated decisions

- Result artifact is primary; global agents output is advisory unless correlated — disposition: pre-resolved(spc-270 A2).
- PID disappearance without proof is unknown, not completed — disposition: pre-resolved(rev-20260831-073033Z F1).
- Probe timeout value may follow existing process timebox conventions — disposition: agent-decides.
- Any transition failure blocks settle — disposition: pre-resolved(spc-270 A2).

## Decision journal

- 2026-08-31 — blocked by tkt-271 because binder fail-close must use the atomic transition contract (source: spc-270 D2).
- 2026-09-01T09:53:18Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #316) [WARN — signal logged, not silently lost]

## Pending decisions

(none)

## Attempts

(none)

## Notes

Do not modify `coordinator.py`; tkt-275 integrates this result contract after merge.

## References

- Review: `rev-20260831-073033Z`
- Spec: `spc-270`
- Prior delivery: `tkt-257`

## Lineage

- Parent spec: **spc-270**
- Parent issue: **#270**
- Primary ticket: **tkt-273**
- Related / sub-tickets: none
- Covers: **A2**
- Blocked by: **#271**
- Merge blocked by: **#271**
- Parallel group: proof-wave-1
- Worktree bind: `tkt-273-deterministic-process-proof`
- Child PRs: none

## Finish

- (none yet)
