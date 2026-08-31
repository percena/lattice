# tkt-276 — True validator warning ratchet

> **TL;DR:** Make warning identity occurrence-safe and enforce a fail-closed, base-compared, only-decreasing migration ratchet.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-270 → tkt-276 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/276 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-08-31T10:07:37Z |
| adopted | false |
| summary | Enforce distinct repeated warnings, fail-closed baseline loading, base comparison, only-decrease and migration deadlines. |
| spec | spc-270 — workflow proof closure follow-up (path: ../../specs/spc-270-workflow-proof-closure-followup.md) |
| covers | A6 |
| blocked_by | #274 |
| merge_blocked_by | #274 |
| parallel_group | proof-wave-2 |
| paths | tools/validate-lattice-artifacts.py (ratchet/migration only), tools/.validator-warning-baseline.txt, tools/tests/lattice-artifacts.bats (ratchet fixtures only), .github/workflows/artifacts.yml, docs/workflow-fsm.md (migration schedule only) |
| solo_merge | yes |
| **primary_ticket** | tkt-276 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-276-warning-ratchet` |
| worktree | sibling `…/lattice.worktrees/tkt-276-warning-ratchet/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A6.1** Warning identity uses stable entity plus occurrence/detail semantics; repeated same-code/path findings remain distinct.
- [ ] **A6.2** Missing, empty where disallowed, malformed, or corrupt baseline fails closed in ratchet mode.
- [ ] **A6.3** CI compares current warnings and baseline against the base branch, forbids additions/baseline growth, permits verified removals, and reports stale entries.
- [ ] **A6.4** Done-Spec PR union and reciprocal-edge warnings have a versioned warning→error schedule enforced by the validator.
- [ ] **A6.5** Fixtures cover repeated occurrence, missing/empty/corrupt baseline, attempted growth, valid removal, stale entry, and migration deadline.

## Approach

Replace the set-like `code + path` signature with structured, portable warning identities and multiset/occurrence comparison. Add an explicit ratchet mode that requires valid current and base baselines, then teach the artifacts workflow to fetch/compare the target base rather than trusting a feature-branch snapshot. Reject baseline growth while allowing verified warning removal and surfacing stale entries. Store migration deadlines as versioned data consumed by the validator, not prose-only dates.

## Anticipated decisions

- Repeated same-file findings must remain distinct — disposition: pre-resolved(spc-270 A6).
- Missing/corrupt ratchet config fails closed — disposition: pre-resolved(spc-270 D5).
- Stable structured identity format and multiset representation — disposition: agent-decides, must remain checkout-portable.
- Warning→error schedule is versioned machine data — disposition: pre-resolved(spc-270 A6).

## Decision journal

- 2026-08-31 — blocked by #274 because both modify validator fixtures; execute after evidence parser lands (source: path-overlap gate).

## Pending decisions

(none)

## Attempts

(none)

## Notes

This ticket owns ratchet and migration logic only; runtime evidence parsing belongs to #274.

## References

- Review: `rev-20260831-073033Z`
- Spec: `spc-270`
- Prior delivery: `tkt-259`

## Lineage

- Parent spec: **spc-270**
- Parent issue: **#270**
- Primary ticket: **tkt-276**
- Related / sub-tickets: none
- Covers: **A6**
- Blocked by: **#274**
- Merge blocked by: **#274**
- Parallel group: proof-wave-2
- Worktree bind: `tkt-276-warning-ratchet`
- Child PRs: none

## Finish

- (none yet)
