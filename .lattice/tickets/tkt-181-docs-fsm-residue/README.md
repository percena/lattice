# tkt-181-docs-fsm-residue

> **TL;DR:** Residual FSM/train-retirement doc drift deferred from tkt-161 A7: morning-triage Step 4 described a pre-tkt-137 world; batch-work said "six" contract items when the contract is five.
> **Kind:** docs · **Priority:** P2
> **Path:** tkt-161 A7 deferred verification → tkt-181 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs, P2 |
| github | https://github.com/percena/lattice/issues/181 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | morning-triage Step 4 rewrite (deferred stamped at trip time) + batch-work five-contract consistency |
| spec | (none — ticket-only) |
| covers | A1, A2 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | docs/morning-triage.md; skills/batch-work/SKILL.md |
| solo_merge | yes |
| **primary_ticket** | tkt-181 |
| **related_tickets** | tkt-161 |
| **worktree_bind** | `tkt-181-docs-fsm-residue` |
| worktree | sibling `…/lattice.worktrees/tkt-181-docs-fsm-residue/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** morning-triage Step 4 describes current behavior (deferred stamped at trip time; human step is re-queue/cancel review); no "Known gap (FSM-2)" future-tense block; summary/recipe-table/NOT-do rows consistent.
- [ ] **A2** batch-work SKILL.md contract count is "five" everywhere (consistent with the invariants table + contract section + flow.md template).

## Notes

- Verification that prompted this ticket (tkt-161 A7): after tkt-150/151 merged, `docs/morning-triage.md` still said fuse-halt tickets "stay `queued`" with a future-tense "Known gap (FSM-2)" block, and `batch-work/SKILL.md` still said "six contract items" at two spots.
- Drift introduced by tkt-132/135/137/138 (pr-142) + the release-train retirement (ADR-005).

## References

- #161 (A7), workflow-fsm.md §1 fuse edge / §2 M2 table, ADR-004 Amendment

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-181**
- Covers: A1, A2
- Blocked by: (none)
- Parallel group: G1

## Finish

- (none yet)
