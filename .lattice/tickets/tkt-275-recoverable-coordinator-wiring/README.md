# tkt-275 — Recoverable coordinator production wiring and concurrency

> **TL;DR:** Wire a concurrency-safe durable coordinator into real batch and finish paths so resume advances work after host restart.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-270 → tkt-275 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/275 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-08-31T10:07:37Z |
| adopted | false |
| summary | Persist and resume the real batch/finish DAG without stale-state regression, lost attempts, or model inference. |
| spec | spc-270 — workflow proof closure follow-up (path: ../../specs/spc-270-workflow-proof-closure-followup.md) |
| covers | A3 |
| blocked_by | #271, #272, #273 |
| merge_blocked_by | #271, #272, #273 |
| parallel_group | proof-wave-2 |
| paths | skills/batch-work/scripts/coordinator.py, skills/batch-work/scripts/tests/coordinator.bats, skills/batch-work/SKILL.md, skills/batch-work/references/flow.md, skills/finish-work/SKILL.md, skills/finish-work/references/flow.md, skills/finish-work/scripts/tests/** (coordinator integration only) |
| solo_merge | yes |
| **primary_ticket** | tkt-275 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-275-recoverable-coordinator-wiring` |
| worktree | sibling `…/lattice.worktrees/tkt-275-recoverable-coordinator-wiring/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A3.1** Real batch-work initializes and persists the complete DAG, marker owner, layer/wave cursor, attempts, PID/PR/OID, and failure class by default.
- [ ] **A3.2** Finish-work consumes the same durable state for multi-PR progression and legacy state has an explicit manual recovery path.
- [ ] **A3.3** State commands lock before read or use revisioned CAS, never regress settled nodes, increment attempts, and remain idempotent.
- [ ] **A3.4** Transition/proof failure cannot settle a node.
- [ ] **A3.5** `resume` after injected host restart actually advances the next eligible node without reconstructing the DAG from artifacts.

## Approach

Harden `coordinator.py` around lock-before-read or revisioned compare-and-swap updates, monotonic node transitions, and incrementing attempts. Make batch initialization and process result recording use it by default, then have multi-PR finish consume the same persisted nodes and proof fields. Implement resume as a deterministic driver for the next eligible node, leaving brief creation and exception interpretation in Skills. Provide an explicit legacy/manual path when no durable state exists; never guess historical batches.

## Anticipated decisions

- Coordinator remains non-inferential — disposition: pre-resolved(spc-270 D4).
- Lock-before-read versus revisioned CAS — disposition: agent-decides based on portability and tests.
- Missing legacy state requires explicit manual recovery, not reconstruction — disposition: pre-resolved(spc-270 Risks).
- Node settle requires successful transition and mutation proof — disposition: pre-resolved(spc-270 A3/A4).

## Decision journal

- 2026-08-31 — blocked by transition, process, and mutation-proof contracts to avoid integrating unstable interfaces (source: conservative ship DAG).

## Pending decisions

(none)

## Attempts

(none)

## Notes

This ticket may update batch/finish orchestration prose but must not redefine transition or proof semantics owned by #271/#272/#273.

## References

- Review: `rev-20260831-073033Z`
- Spec: `spc-270`
- Prior delivery: `tkt-258`

- NOTICED: skills/_lattice-lib/scripts/finish-ledger.sh — commit_transaction IO failure swallowed as warn+exit0 (out-of-paths, 2026-09-01); related to the finish-ledger cancel-entry bug.
- NOTICED: plugins/lattice/scripts/detect-git-branch-op.py — `git branch -f` force-create classified op=none (strict-profile bypass); `git checkout <treeish> -- <path>` file-restore misclassified as branch-switch (out-of-paths, 2026-09-01).
- NOTICED: skills/finish-work/scripts/update-pr-base.sh — base-OID REST fetch omits --hostname (GHE host gap, #311 follow-up; out-of-paths, 2026-09-01).

## Lineage

- Parent spec: **spc-270**
- Parent issue: **#270**
- Primary ticket: **tkt-275**
- Related / sub-tickets: none
- Covers: **A3**
- Blocked by: **#271, #272, #273**
- Merge blocked by: **#271, #272, #273**
- Parallel group: proof-wave-2
- Worktree bind: `tkt-275-recoverable-coordinator-wiring`
- Child PRs: none

## Finish

- (none yet)
