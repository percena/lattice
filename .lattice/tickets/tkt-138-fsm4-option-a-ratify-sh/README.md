# tkt-138-fsm4-option-a-ratify-sh

> **TL;DR:** New ratify.sh writes Decision journal + parked→queued status flip in one git commit (FSM-4 Option A, chosen in tkt-136)
> **Kind:** feat · **Priority:** P2
> **Path:** rev-20260827-064527Z → tkt-136 (decision) → tkt-138 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/138 |
| status | queued |
| adopted | false |
| summary | Add ratify.sh single-commit script for parked→queued atomicity (FSM-4 Option A) |
| spec | none — ticket-only from tkt-136 decision |
| covers | rev FSM-4 |
| blocked_by | (none) |
| parallel_group | G2 (serial with tkt-132 on start-work + workflow-fsm.md) |
| paths | skills/_lattice-lib/scripts/ratify.sh, skills/start-work/SKILL.md, docs/workflow-fsm.md |
| solo_merge | no (one-PR with G2 set) |
| **primary_ticket** | tkt-138 (this issue) |
| **related_tickets** | tkt-132 (G2 serial) |
| **worktree_bind** | tkt-138-fsm4-option-a-ratify-sh |
| prs | (none) |

## Acceptance (this slice only)

- [ ] **A1** ratify.sh exists; takes binder path + decision text; writes journal + status flip in one commit
- [ ] **A2** start-work:89 cites ratify.sh instead of bare atomically one-write claim
- [ ] **A3** docs/workflow-fsm.md §2 + §5 updated: single-commit, crash window narrowed
- [ ] **A4** bats: ratify.sh on parked fixture leaves queued + journal entry in one commit; crash sim leaves binder unchanged

## Approach

New script skills/_lattice-lib/scripts/ratify.sh: args --binder <path> --decision <text>. Appends decision to binder ## Decision journal (append-only), flips status: parked → queued in the field table, then git add + git commit -m ratify(tkt-N): <summary> in one commit. Update start-work:89 to cite the script (ratify action calls ratify.sh). Update workflow-fsm.md §2 parked→queued transition note and §5 to say single-commit (reviewable pair), crash window narrowed not eliminated.

## Anticipated decisions

- Script argument shape (flag vs positional) — disposition: agent-decides (reversible, ticket-local; follow _lattice-lib script conventions)
- Whether to also handle deferred→queued (re-schedule) — disposition: pre-resolved (no; that stays a human transition per ADR-004 §1 white-list)

## References

- Decision: tkt-136 (FSM-4 = Option A), ADR-004 Amendment (tkt-136)
- Reviews: rev-20260827-064527Z (Finding 2), rev-20260827-102420Z (Finding 7)
- ADR: ADR-004 §6

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-138 · Parallel group: G2 · Worktree bind: tkt-138-fsm4-option-a-ratify-sh

## Finish

- (none yet)
