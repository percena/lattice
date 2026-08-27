# tkt-136-fsm2-fsm4-policy-decision

> **TL;DR:** Operator picks an option for FSM-2 (fuse-halt SoT) and FSM-4 (parked→queued atomicity) so implementation tickets can be filed
> **Kind:** spike · **Priority:** P2
> **Path:** rev-20260827-064527Z → tkt-136 → (pr-…)

| Field | Value |
| --- | --- |
| kind | spike |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/136 |
| status | queued |
| adopted | false |
| summary | FSM-2/FSM-4 design policy decision (fuse-halt SoT + parked→queued atomicity) |
| spec | none — ticket-only from rev-20260827-064527Z + rev-20260827-102420Z F7 |
| covers | rev F7 |
| blocked_by | (none — blocked on operator, not on another ticket) |
| parallel_group | (none — blocked on operator decision) |
| paths | docs/workflow-fsm.md, docs/adr/004* |
| solo_merge | yes (once decided) |
| **primary_ticket** | tkt-136 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-136-fsm2-fsm4-policy-decision |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** Operator picks FSM-2 option (A/B/C/D) with one-line rationale
- [ ] **A2** Operator picks FSM-4 option (A/B/C) with one-line rationale
- [ ] **A3** Chosen options documented in ADR-004 amendment
- [ ] **A4** Implementation tickets filed (one per gap, citing chosen option)

## Approach

This is a decision spike — no implementation. Operator reviews the four FSM-2 options and three FSM-4 options (listed in issue body + rev-20260827-064527Z), picks one each, and the decision is recorded in a dated ADR-004 amendment. Once decided, two implementation tickets are filed (separate from this spike). Recommended: FSM-2 → Option B (stamp deferred+reason at trip time); FSM-4 → Option A (ratify.sh single-commit).

## Anticipated decisions

- FSM-2 option (A/B/C/D) — disposition: must-ask (irreversible design decision, cross-contract)
- FSM-4 option (A/B/C) — disposition: must-ask (irreversible design decision, cross-contract)

## Pending decisions

- FSM-2: accept blocked-by-failure/fuse-halted enum (A) vs. stamp deferred (B) vs. read prior report (C) vs. accept gap (D)? · context: ADR-004 §6 SoT honesty · default-if-unanswered: D (accept + document)
- FSM-4: ratify.sh single-commit (A) vs. validator snapshot-diff invariant (B) vs. accept soft claim (C)? · context: ADR-004 §6, Markdown no transactions · default-if-unanswered: C (accept + document)

## References

- GitHub issue body is SoT for long prose
- Reviews: rev-20260827-064527Z (Findings 1 + 2), rev-20260827-102420Z (Finding 7)
- ADR: ADR-004 §6, §1

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-136 · Parallel group: (none) · Worktree bind: tkt-136-fsm2-fsm4-policy-decision

## Finish

- (none yet)
