# tkt-471-recoverable-batch-coordinator

> **TL;DR:** Make the batch coordinator persist the complete execution plan and apply restart-safe, idempotent commands.
> **Kind:** fix · **Priority:** P0
> **Path:** spc-475 → tkt-471 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P0 |
| labels | bug, P0 |
| github | https://github.com/percena/lattice/issues/471 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-04T05:03:12Z |
| updated | 2026-09-05T04:12:23Z |
| adopted | false |
| summary | Persist complete versioned DAG before spawn; add resume driver; CAS/monotonic cursor; idempotent terminal transitions; fault tests |
| spec | spc-475 — Review follow-up round 2 (path: ../../specs/spc-475-review-followup-r2.md) |
| covers | A7, A8, A9, A10, A11, A12, A13 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/batch-work/scripts/lib/coordinator.py, skills/batch-work/scripts/run-process-wave.sh, skills/batch-work/** |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-471 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-471-recoverable-batch-coordinator` |
| worktree | sibling `…/lattice.worktrees/tkt-471-recoverable-batch-coordinator/` |
| prs | pr-477 — https://github.com/percena/lattice/pull/477 |

## Acceptance (this slice)

- [x] **A7** Complete future layers/waves are durable before the first worker starts; plan hash/revision identifies the execution plan.
- [x] **A8** Restart between waves returns the real next unspawned node and a production driver can continue it.
- [x] **A9** Init/load failure prevents spawn; canonical record/cursor persistence failures cannot be warning-only success.
- [x] **A10** Stale marker/node writes cannot regress a cursor already advanced to a later tuple.
- [x] **A11** Replaying the same failed/timeout/unknown command returns already-applied success and emits one binder transition.
- [x] **A12** Transition failure remains retryable and never marks the node settled prematurely.
- [x] **A13** Multi-process fault tests cover stale writers, terminal replay, pre-spawn restart, and reservation recovery.

## Approach

1. Add `save_plan()` / `load_plan()` to coordinator: serialize the complete DAG + plan hash before first spawn.
2. Add a production `resume()` driver that loads durable state and continues from the last cursor.
3. Wrap command application under one lock with revision/CAS and monotonic cursor semantics.
4. Add idempotency/reservation for terminal node transitions.
5. Make record-spawn and cursor persistence failures machine-fatal.
6. Add multi-process fault tests.

## Anticipated decisions

- DAG serialization format (JSON vs msgpack) — disposition: agent-decides (JSON for readability/debuggability).
- CAS mechanism (file-based revision vs flock) — disposition: agent-decides (file-based revision with atomic rename).

## Decision journal

<!-- Append-only during execution. -->

## Finish

- pr-477 merged: 2026-09-05T04:09:30Z — https://github.com/percena/lattice/pull/477 (base merge)
- issue #471 closed: 2026-09-05T04:10:21Z — https://github.com/percena/lattice/issues/471
