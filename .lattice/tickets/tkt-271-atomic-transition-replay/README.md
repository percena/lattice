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
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-08-31T16:00:04Z |
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

- [x] **A1.1** One API locks the binder, reads the real prior status/coupled fields, validates the versioned edge, and atomically writes status/wait_reason/updated plus one ticket-bound ledger entry. — `transition-api.py commit`: dir-flock → read prior status/wait_reason → edge + escape + coupled wait_reason validation → temp binder + ledger append + atomic `os.replace`; proven by `transition-api.bats` #10/#14.
- [x] **A1.2** Validation, ledger, or binder-write failure leaves neither partial state nor a misleading transition record. — fail-close ordering (validate → temp → ledger → rename) + `_rollback_ledger` on rename failure; proven by fault-injection `transition-api.bats` #18 (chmod 000 ledger dir → exit 3, binder byte-identical, no temp residue, no ledger growth).
- [ ] **A1.3** All production M2 writers use the guarded API while preserving existing CLI and human-adjudicated escape semantics. — **remaining (increment 2)**: `commit` exists; stamp-pr-open/finish-ledger/bump-fix-cycle/ratify/spec-supersede/reconcile-state still call `record` or stamp directly.
- [x] **A1.4** Replay rejects discontinuity, wrong ticket identity, illegal/omitted transitions, and final ledger-to-binder snapshot mismatch. — `replay-ledger` strengthened with identity/continuity/snapshot invariants; proven by `transition-api.bats` #19/#20/#21/#22.
- [ ] **A1.5** Schema↔FSM parity covers owner, guard, reason, escape, trace, and metric; drift fails CI. — **remaining (increment 2)**: `transition-parity.bats` asserts (from,to) set-equality + escape-set equality only; field-level parity across lib↔validator↔docs not yet asserted.

## Approach

Extend `transition-api.py` from append-only recording into a binder-bound transaction with an exclusive lock and typed coupled-field patch. Keep the versioned table as the edge source of truth, then migrate each existing status writer behind a compatibility call rather than rewriting its public CLI. Replay each ticket stream in order, check identity and continuity, and compare the final `to` plus coupled fields with the current binder. Add per-writer regression and injected-failure fixtures before switching canonical callers. Touch only shared transition/writer surfaces; batch process and coordinator code consume this API in later tickets.

## Anticipated decisions

- Transaction boundary includes binder mutation and ledger append — disposition: pre-resolved(spc-270 A1).
- Git remains durable history, but replay requires complete per-ticket transition records — disposition: pre-resolved(rev-20260831-073033Z).
- Compatibility shims may preserve writer CLIs during migration — disposition: agent-decides, provided no bypass remains in canonical paths.
- Escape-required side-state transitions remain human-adjudicated — disposition: pre-resolved(ADR-007 / spc-270 D1).

## Decision journal

- 2026-08-31 — foundation runs before process/coordinator slices to avoid duplicate state mutation semantics (source: spc-270 D2).
- 2026-08-31 — increment 1 delivered: atomic `commit` + replay identity/continuity/snapshot invariants + fault-injection fixtures. `record` kept as the ledger-only primitive so non-canonical/test callers and the not-yet-migrated writers keep working; `commit` is the canonical path writers will route to in increment 2 (A1.3). No bypass is introduced — `commit` enforces edge+escape+coupled-field; `record` does not mutate the binder, so a writer that only calls `record` leaves the binder status row untouched (replay's snapshot check would flag any drift). Source: spc-270 A1 Approach ("add fixtures before switching canonical callers").

## Pending decisions

(none)

## Attempts

(none)

## Notes

Foundation is intentionally serial. A2/A3 tickets may call the resulting API but must not redefine transition semantics.

Increment 1 (this commit) lands the atomic `commit` transaction + the strengthened replay invariants + fault-injection fixtures; A1.1/A1.2/A1.4 are proven. Increment 2 remains: migrate the six M2 writers behind `commit` (A1.3) and assert field-level schema↔FSM parity (A1.5). Do not open the PR until A1.3 leaves no `record`/direct-stamp bypass in a canonical writer path.

Replay invariant surfaced 6 pre-existing dev-base drift cases (tkt-256/261/284/285/286/287): ledger final `to`=pr-open but binder `status`=closed — finish-ledger closes the binder without recording a `pr-open -> closed` ledger entry (the exact bypass A1.3 cures). These are NOT newly failing CI (the validator's inline replay only checks edge legality; `replay-ledger` is invoked only in tests against a tmp home), but they are the real defect A1.3 will close. Disposition: increment 2 migrates finish-ledger to record the close flip, after which these ledgers and binders reconcile.

- NOTICED: `skills/_lattice-lib/scripts/tests/{stamp-pr-open,ratify,bump-fix-cycle}.bats` write a real `.lattice/.transition-ledger/tkt-7.jsonl` into the repo home (not a tmp dir) and leave it as untracked residue after a suite run — out-of-paths test hygiene, 2026-08-31. Not folded into this slice; a later sweep ticket is the disposition.

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
