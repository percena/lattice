# tkt-442-fix-gha-injection

> **TL;DR:** Route workflow_dispatch inputs through env vars to prevent expression injection
> **Kind:** bug · **Priority:** P1
> **Path:** spc-441 → tkt-442 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/442 |
| status | closed |
| fix_cycles | 0 |
| created | 2026-09-03T15:43:52Z |
| updated | 2026-09-03T16:37:25Z |
| adopted | false |
| summary | Fix GHA expression injection in finish-stamp.yml |
| spec | spc-441 — project-wide hardening sweep (path: ../../specs/spc-441-hardening-sweep.md) |
| covers | A1 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | .github/workflows/finish-stamp.yml |
| solo_merge | yes |
| autonomy | 4 |
| primary_ticket | tkt-442 |
| related_tickets | (none) |

## Acceptance (this slice)

- [x] **A1** No `${{ inputs.* }}` or `${{ github.event.* }}` appears directly in any `run:` block — all route through `env:`

## Approach

In the "Resolve event inputs" step, move all `${{ inputs.* }}` and `${{ github.event.* }}` references to an `env:` block. Reference as `$VAR` in shell. Similarly protect the "Verify local stamp" step's `steps.evt.outputs.*` references. Touch-set: `.github/workflows/finish-stamp.yml`.

## Anticipated decisions

- (none — straightforward mechanical fix)

## Decision journal

## Notes

## References

- Spec: spc-441
- Parent issue: #441

## Lineage

- Parent spec: **spc-441**
- Parent issue: **#441**
- Primary ticket: **tkt-442**
- Covers: **A1**
- Parallel group: G1

## Assets

## Finish


- pr-450 merged: 2026-09-03T16:36:40Z — https://github.com/percena/lattice/pull/450 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #442 closed: 2026-09-03T16:37:04Z (reason: completed) — https://github.com/percena/lattice/issues/442
