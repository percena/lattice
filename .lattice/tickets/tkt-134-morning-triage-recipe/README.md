# tkt-134-morning-triage-recipe

> **TL;DR:** Add docs/morning-triage.md — the attended recipe for consuming a night batch (currently scattered across skill prose)
> **Kind:** docs · **Priority:** P3
> **Path:** rev-20260827-102420Z → tkt-134 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | documentation, P3 |
| github | https://github.com/percena/lattice/issues/134 |
| status | queued |
| adopted | false |
| summary | Add morning-triage recipe doc (digest → ratify → disposition → merge) |
| spec | none — ticket-only from rev-20260827-102420Z F4 |
| covers | rev F4 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | docs/morning-triage.md, docs/workflow-fsm.md |
| solo_merge | yes |
| **primary_ticket** | tkt-134 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-134-morning-triage-recipe |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** docs/morning-triage.md exists with step-by-step recipe (digest → ratify → disposition → stamp → verdicts → finish-work)
- [ ] **A2** Cross-linked from workflow-fsm.md §3 and day-phase.md
- [ ] **A3** Each step cites the skill that owns the action

## Approach

New file docs/morning-triage.md. Six sections: (1) read review-delivery digest (ranked PRs + ratification queue + NOTICED sweep); (2) ratify decision-journal entries (M3 ×2 promotion path); (3) disposition stuck tickets (wait_reason: unblock → re-queue; wait_reason: re-scope → Spec revision; cancel → closed); (4) stamp deferred on fuse-halted/abandoned tickets; (5) consume PR verdicts (auto-pass/ratify-then-pass/deep-review); (6) run finish-work per PR. Cross-link from workflow-fsm.md §3 + day-phase.md. Cite skills, don't duplicate prose.

## Anticipated decisions

- (none — pure doc, no decisions)

## References

- GitHub issue body is SoT for long prose
- Review: rev-20260827-102420Z (Finding 4)
- FSM: docs/workflow-fsm.md §3, §5

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-134 · Parallel group: G1 · Worktree bind: tkt-134-morning-triage-recipe

## Finish

- (none yet)
