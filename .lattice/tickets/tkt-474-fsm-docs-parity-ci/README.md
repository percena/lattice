# tkt-474-fsm-docs-parity-ci

> **TL;DR:** Reconcile final FSM guarantees and ensure docs-only FSM changes trigger parity CI.
> **Kind:** docs · **Priority:** P2
> **Path:** spc-475 → tkt-474 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs, P2 |
| github | https://github.com/percena/lattice/issues/474 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-04T05:03:52Z |
| updated | 2026-09-05T04:27:58Z |
| adopted | false |
| summary | FSM document reconciliation; parity CI path filter; contract test for workflow filter coverage |
| spec | spc-475 — Review follow-up round 2 (path: ../../specs/spc-475-review-followup-r2.md) |
| covers | A26, A27, A28, A29, A30 |
| blocked_by | tkt-470, tkt-471, tkt-472, tkt-473 |
| merge_blocked_by | (none) |
| parallel_group | serial finalization in tkt-472 ship slot |
| paths | docs/workflow-fsm.md, .github/workflows/lattice-scripts.yml |
| solo_merge | no — ships in the #472 worktree/PR |
| autonomy | 3 |
| **primary_ticket** | tkt-474 (this issue) |
| **related_tickets** | tkt-470, tkt-471, tkt-472, tkt-473 |
| **worktree_bind** | `tkt-472-crash-recoverable-transitions` (shared) |
| worktree | sibling `…/lattice.worktrees/tkt-472-crash-recoverable-transitions/` |
| prs | pr-478 — https://github.com/percena/lattice/pull/478 |

## Acceptance (this slice)

- [x] **A26** Documentation accurately describes actual transition replay and no longer claims history is not replayed.
- [x] **A27** Documentation describes the final protected-branch repair, durable coordinator, recoverable operation, and guarded Spec semantics without overclaiming.
- [x] **A28** A docs-only change to `docs/workflow-fsm.md` triggers the `bats` workflow.
- [x] **A29** Schema/docs single-sided changes fail parity.
- [x] **A30** Static regression test fails if the parity document path disappears from workflow filters.

## Approach

1. Update `docs/workflow-fsm.md` once #470-#473 contracts are final.
2. Add `docs/workflow-fsm.md` to push and pull-request workflow filters in `lattice-scripts.yml`.
3. Add a contract test that proves parity inputs are covered by workflow paths.
4. Keep legacy warning baseline unchanged.

## Anticipated decisions

- None expected (docs reconciliation once implementation is final).

## Decision journal

<!-- Append-only during execution. -->

## Finish

- pr-478 merged: 2026-09-05T04:27:06Z — https://github.com/percena/lattice/pull/478 (base merge)
- issue #474 closed: 2026-09-05T04:27:27Z — https://github.com/percena/lattice/issues/474
