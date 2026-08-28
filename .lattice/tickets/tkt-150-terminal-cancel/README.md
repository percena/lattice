# tkt-150-terminal-cancel

> **TL;DR:** Make cancel and closed-without-merge reach a truthful terminal binder from every legal working state.
> **Kind:** bug · **Priority:** P1
> **Path:** rev-20260828-082751Z → tkt-150 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/150 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | Close all legal working states on human cancel and support no-PR cancellation |
| spec | (none — ticket-only) |
| covers | A1, A2, A3, A4, A5 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/finish-ledger.sh; skills/_lattice-lib/scripts/tests/finish-ledger.bats; skills/finish-work/SKILL.md; skills/finish-work/references/flow.md; skills/start-work/SKILL.md; docs/morning-triage.md; docs/workflow-fsm.md |
| solo_merge | yes |
| **primary_ticket** | tkt-150 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-150-terminal-cancel` |
| worktree | sibling `…/lattice.worktrees/tkt-150-terminal-cancel/` |
| prs | pr-156 — https://github.com/percena/lattice/pull/156 |

## Acceptance

- [x] **A1** Human cancel/terminal issue evidence closes `open|queued|in-progress|parked|stuck|pr-open|rework|deferred` without leaving a working binder.
- [x] **A2** Closed-without-merge never claims `mergedAt`; merged outcomes retain firm merge evidence and surface anomalous prior states without losing external truth.
- [x] **A3** A no-PR cancel writes a valid dated Finish ledger and `closed` status without fabricated PR evidence.
- [x] **A4** Unknown/open external state fails closed; containment, concurrency, atomicity, and idempotency remain covered.
- [x] **A5** Full `bash tools/ci-local.sh` passes.

## Approach

- Separate terminal evidence from transition provenance: external closed truth must not leave the binder working, while anomalous prior states remain visible as warnings/ledger context.
- Extend the working-state rewrite to the complete FSM vocabulary.
- Add a bounded no-PR cancel mode/helper requiring explicit human-supplied reason and firm close time or verified issue closure.
- Reuse the existing path containment, directory lock, atomic replacement, and repository identity checks.
- Replace the parked-preservation regression with a cancel-from-any-state matrix and negative open/unknown cases.
- Align finish-work/start-work/morning-triage wording only where the executable contract changes.

## Anticipated decisions

- Merged PR observed from an unexpected working state — disposition: agent-decides; preserve terminal external truth and emit explicit anomaly evidence rather than strand the binder.
- No-PR cancel interface — disposition: agent-decides; prefer the smallest adjacent mode/helper with explicit reason and no fabricated PR row.

## Decision journal

## Pending decisions

## Attempts

## Notes

## References

- Review: `rev-20260828-082751Z`
- FSM: `docs/workflow-fsm.md`

## Lineage

- Parent spec: none
- Parent issue: none
- Primary ticket: **tkt-150**
- Related tickets: none
- Covers: **A1, A2, A3, A4, A5**
- Blocked by: none
- Parallel group: G1
- Worktree bind: `tkt-150-terminal-cancel`

## Finish


- pr-156 merged: 2026-08-28T13:21:39Z — https://github.com/percena/lattice/pull/156 (base merge)
- issue #150 closed: 2026-08-28T13:24:41Z — https://github.com/percena/lattice/issues/150
