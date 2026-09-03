# tkt-448-split-status-row-guard

> **TL;DR:** Extract L3 status-row guard from intercept-shippable-write.sh into its own file
> **Kind:** refactor · **Priority:** P2
> **Path:** spc-441 → tkt-448 → (pr-…)

| Field | Value |
| --- | --- |
| kind | refactor |
| priority | P2 |
| labels | refactor, P2 |
| github | https://github.com/percena/lattice/issues/448 |
| status | closed |
| fix_cycles | 0 |
| created | 2026-09-03T15:44:31Z |
| updated | 2026-09-03T16:52:11Z |
| adopted | false |
| summary | Split L3 status-row guard into plugins/lattice/hooks/lib/status-row-guard.sh |
| spec | spc-441 — project-wide hardening sweep (path: ../../specs/spc-441-hardening-sweep.md) |
| covers | A7 |
| blocked_by | tkt-445 |
| parallel_group | G2 |
| paths | plugins/lattice/hooks/intercept-shippable-write.sh, plugins/lattice/hooks/lib/ |
| solo_merge | yes |
| autonomy | 2 |
| primary_ticket | tkt-448 |
| related_tickets | (none) |

## Acceptance (this slice)

- [x] **A7** L3 status-row guard logic is in a separate file sourced by the main hook; both existing test files pass

## Approach

Move _status_cell, _status_row_count, _status_row_guard functions (~lines 155-260) to lib/status-row-guard.sh. Main hook sources it. No behavior change. Touch-set: intercept-shippable-write.sh, lib/status-row-guard.sh (new).

## Anticipated decisions

- (none pre-resolved)

## Pending decisions

- Plugin version bump needed? Hook file restructure changes plugin layout — bump patch?

## Decision journal

## Notes

## References

- Spec: spc-441
- ADR-012 §2 (L3 status-row guard)

## Lineage

- Parent spec: **spc-441**
- Parent issue: **#441**
- Primary ticket: **tkt-448**
- Covers: **A7**
- Blocked by: tkt-445
- Parallel group: G2

## Assets

## Finish


- pr-456 merged: 2026-09-03T16:49:31Z — https://github.com/percena/lattice/pull/456 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #448 closed: 2026-09-03T16:50:19Z (reason: completed) — https://github.com/percena/lattice/issues/448
