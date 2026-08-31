# tkt-271 — Atomic transition mutation and replay completeness

> **TL;DR:** Make the versioned transition contract the atomic mutation chokepoint for every M2 writer and prove replay completeness.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-270 → tkt-271 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/271 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-08-31T10:07:37Z |
| adopted | false |
| summary | Atomically mutate binder state and ledger through one guarded transition API; replay real continuity and final snapshot. |
| spec | spc-270 — workflow proof closure follow-up (path: ../../specs/spc-270-workflow-proof-closure-followup.md) |
| covers | A1 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | foundation |
| paths | skills/_lattice-lib/scripts/transition-api.py, skills/_lattice-lib/scripts/lib/transition_table.py, skills/_lattice-lib/scripts/lib/status_vocab.py, skills/_lattice-lib/scripts/{finish-ledger,bump-fix-cycle,ratify,spec-supersede,stamp-pr-open,reconcile-state}.sh, skills/_lattice-lib/scripts/tests/**, docs/workflow-fsm.md, tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-271 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-271-atomic-transition-replay` |
| worktree | sibling `…/lattice.worktrees/tkt-271-atomic-transition-replay/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1.1** One API locks the binder, reads the real prior status/coupled fields, validates the versioned edge, and atomically writes status/wait_reason/updated plus one ticket-bound ledger entry.
- [ ] **A1.2** Validation, ledger, or binder-write failure leaves neither partial state nor a misleading transition record.
- [ ] **A1.3** All production M2 writers use the guarded API while preserving existing CLI and human-adjudicated escape semantics.
- [ ] **A1.4** Replay rejects discontinuity, wrong ticket identity, illegal/omitted transitions, and final ledger-to-binder snapshot mismatch.
- [ ] **A1.5** Schema↔FSM parity covers owner, guard, reason, escape, trace, and metric; drift fails CI.

## Approach

Extend `transition-api.py` from append-only recording into a binder-bound transaction with an exclusive lock and typed coupled-field patch. Keep the versioned table as the edge source of truth, then migrate each existing status writer behind a compatibility call rather than rewriting its public CLI. Replay each ticket stream in order, check identity and continuity, and compare the final `to` plus coupled fields with the current binder. Add per-writer regression and injected-failure fixtures before switching canonical callers. Touch only shared transition/writer surfaces; batch process and coordinator code consume this API in later tickets.

## Anticipated decisions

- Transaction boundary includes binder mutation and ledger append — disposition: pre-resolved(spc-270 A1).
- Git remains durable history, but replay requires complete per-ticket transition records — disposition: pre-resolved(rev-20260831-073033Z).
- Compatibility shims may preserve writer CLIs during migration — disposition: agent-decides, provided no bypass remains in canonical paths.
- Escape-required side-state transitions remain human-adjudicated — disposition: pre-resolved(ADR-007 / spc-270 D1).

## Decision journal

- 2026-08-31 — foundation runs before process/coordinator slices to avoid duplicate state mutation semantics (source: spc-270 D2).

## Pending decisions

(none)

## Attempts

(none)

## Notes

Foundation is intentionally serial. A2/A3 tickets may call the resulting API but must not redefine transition semantics.

## References

- Review: `rev-20260831-073033Z`
- Spec: `spc-270`
- Prior delivery: `tkt-255` / `spc-254`

## Lineage

- Parent spec: **spc-270**
- Parent issue: **#270**
- Primary ticket: **tkt-271**
- Related / sub-tickets: none
- Covers: **A1**
- Blocked by: none
- Merge blocked by: none
- Parallel group: foundation
- Worktree bind: `tkt-271-atomic-transition-replay`
- Child PRs: none

## Finish

- (none yet)
