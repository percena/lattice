# tkt-136-fsm2-fsm4-policy-decision

> **TL;DR:** Operator picked FSM-2=Option B, FSM-4=Option A; impl tickets filed (tkt-137, tkt-138)
> **Kind:** spike · **Priority:** P2
> **Path:** rev-20260827-064527Z → tkt-136 → (closed — decision resolved)

| Field | Value |
| --- | --- |
| kind | spike |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/136 |
| status | closed |
| adopted | false |
| summary | FSM-2/FSM-4 design policy decision — resolved (FSM-2=B, FSM-4=A) |
| spec | none — ticket-only from rev-20260827-064527Z + rev-20260827-102420Z F7 |
| covers | rev F7 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | docs/workflow-fsm.md, docs/adr/004* |
| solo_merge | yes |
| **primary_ticket** | tkt-136 (this issue) |
| **related_tickets** | tkt-137 (FSM-2-B impl), tkt-138 (FSM-4-A impl) |
| **worktree_bind** | tkt-136-fsm2-fsm4-policy-decision |
| prs | (none) |

## Acceptance (this slice)

- [x] **A1** Operator picks FSM-2 option (A/B/C/D) — **Option B** (stamp deferred+reason at trip time; SoT honest without new enum values)
- [x] **A2** Operator picks FSM-4 option (A/B/C) — **Option A** (ratify.sh single-commit; crash window narrowed to reviewable pair)
- [x] **A3** Chosen options documented in ADR-004 Amendment (tkt-136, dated 2026-08-27)
- [x] **A4** Implementation tickets filed: tkt-137 (FSM-2-B), tkt-138 (FSM-4-A)

## Notes

- Decision resolved 2026-08-27 by operator (M1n9X) per rev-20260827-102420Z recommendation
- ADR-004 Amendment records both options with rationale

## References

- Reviews: rev-20260827-064527Z (Findings 1 + 2), rev-20260827-102420Z (Finding 7)
- ADR: ADR-004 Amendment (tkt-136)
- Impl: tkt-137 (FSM-2-B), tkt-138 (FSM-4-A)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-136 · Parallel group: (none) · Worktree bind: tkt-136-fsm2-fsm4-policy-decision

## Finish

- issue #136 closed: 2026-08-27 — decision resolved (FSM-2=Option B, FSM-4=Option A); no PR (decision spike); impl tickets: tkt-137 (FSM-2-B), tkt-138 (FSM-4-A); ADR-004 Amendment stamped
