# tkt-151-artifact-state-invariants

> **TL;DR:** Enforce declared Spec, Review, and coupled ticket state invariants in CI and repair current artifact drift.
> **Kind:** bug · **Priority:** P1
> **Path:** rev-20260828-082751Z → tkt-151 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/151 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | Reject semantically impossible artifacts and reconcile current Spec terminal state |
| spec | (none — ticket-only) |
| covers | A1, A2, A3, A4, A5, A6, A7 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | tools/validate-lattice-artifacts.py; tools/tests/lattice-artifacts.bats; tools/tests/fixtures/lattice-artifacts/**; skills/create-tickets/references/templates/ticket-binder.md; .lattice/specs/**; skills/batch-work/SKILL.md; skills/batch-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-151 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-151-artifact-state-invariants` |
| worktree | sibling `…/lattice.worktrees/tkt-151-artifact-state-invariants/` |
| prs | pr-157 — https://github.com/percena/lattice/pull/157 |

## Acceptance

- [x] **A1** Unknown Spec status, unknown Review status/outcome, or concluded Review without exactly one valid outcome fails validation.
- [x] **A2** `done` with open non-deferred A* or contradictory display status fails; `superseded` requires valid linkage.
- [x] **A3** `stuck` requires `wait_reason: unblock|re-scope`; `deferred` requires an allowed machine-readable reason; contradictory values fail.
- [x] **A4** Cancel and merged Finish evidence require terminal `closed` whenever that fact is provable from one snapshot.
- [x] **A5** Current Specs are reconciled from actual landed evidence with no fictional checkbox or PR updates.
- [x] **A6** Batch-work documentation has one unambiguous mapping for each not-spawned reason.
- [x] **A7** Fixture-backed tests and full `bash tools/ci-local.sh` pass.

## Approach

- Extend the standalone validator with explicit Spec and Review vocabularies and small snapshot-provable guard functions.
- Parse only authoritative frontmatter/first-table/Acceptance/Finish sections; avoid whole-document prose matches.
- Add coupled ticket field parsing for `wait_reason` and a new/established deferred-reason representation.
- Preserve the stated boundary: report illegal snapshots, do not claim to replay Git transition history.
- Add focused fixtures for each accepted/rejected family and current-law lazy-migration decisions.
- Reconcile `spc-116`, `spc-12`, and `spc-4` from landed tickets, PRs, and Acceptance evidence.
- Clarify fuse-halted, blocked-by-failure, workspace-failed, and not-selected wording in batch docs.

## Anticipated decisions

- Deferred reason field shape — disposition: agent-decides; prefer a first-table field with a small enum and lazy migration only where current artifacts require it.
- Historical Review strictness — disposition: agent-decides; enforce current files without breaking explicitly documented legacy IDs.
- Spec done guard deferred syntax — disposition: agent-decides; accept only an explicit per-A* deferred marker, never free-form nearby prose.

## Decision journal

- 2026-08-28 — Deferred reason field shape: extended the existing `wait_reason` field-table row to carry deferred reasons too (`fuse-halt | blocked-by-failure`), rather than a new `deferred_reason` row. Reuse is grep-able, lower-friction, and the validator already parses the first table. Reversible + ticket-local. (anticipated decision resolved)
- 2026-08-28 — Historical Review strictness: enforce current files without special legacy-ID exemptions. No documented legacy Review ids require an escape; unknown status/outcome fails uniformly. (anticipated decision resolved)
- 2026-08-28 — Spec done guard deferred syntax: accept only an explicit per-A* `(deferred)` inline marker or `~~` strikethrough on the same acceptance line; never free-form nearby prose. Machine-readable and scoped to the Acceptance section. (anticipated decision resolved)
- 2026-08-28 — Spec header status mismatch severity: error when the spec is terminal (`done`/`superseded`) — a terminal spec's display must match — and warning for `draft`/`locked` (display drift, lazy migration). Reversible.

## Pending decisions

## Attempts

## Notes

## References

- Review: `rev-20260828-082751Z`
- Validator: `tools/validate-lattice-artifacts.py`

## Lineage

- Parent spec: none
- Parent issue: none
- Primary ticket: **tkt-151**
- Related tickets: none
- Covers: **A1, A2, A3, A4, A5, A6, A7**
- Blocked by: none
- Parallel group: G1
- Worktree bind: `tkt-151-artifact-state-invariants`

## Finish

- (none yet)
