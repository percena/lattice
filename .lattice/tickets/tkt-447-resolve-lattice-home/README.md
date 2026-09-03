# tkt-447-resolve-lattice-home

> **TL;DR:** Extract duplicated _lattice-home.sh walk-up loop into a shared function
> **Kind:** refactor · **Priority:** P2
> **Path:** spc-441 → tkt-447 → (pr-…)

| Field | Value |
| --- | --- |
| kind | refactor |
| priority | P2 |
| labels | refactor, P2 |
| github | https://github.com/percena/lattice/issues/447 |
| status | queued |
| fix_cycles | 0 |
| created | 2026-09-03T15:44:31Z |
| updated | 2026-09-03T15:44:31Z |
| adopted | false |
| summary | Extract shared resolve_lattice_lib_scripts function from duplicated walk-up loop |
| spec | spc-441 — project-wide hardening sweep (path: ../../specs/spc-441-hardening-sweep.md) |
| covers | A6 |
| blocked_by | (none) |
| parallel_group | G2 |
| paths | skills/_lattice-lib/scripts/_lattice-home.sh, skills/finish-work/scripts/alignment-check.sh, skills/finish-work/scripts/ci-gate-check.sh, skills/_lattice-lib/scripts/queue-health.sh |
| solo_merge | yes |
| autonomy | 3 |
| primary_ticket | tkt-447 |
| related_tickets | (none) |

## Acceptance (this slice)

- [x] **A6** Walk-up loop in alignment-check.sh, ci-gate-check.sh, queue-health.sh replaced by a shared function call; all bats tests pass

## Approach

Add `resolve_lattice_lib_scripts()` to _lattice-home.sh. Each consumer sources _lattice-home.sh (some already do) then calls the function. Touch-set: _lattice-home.sh, alignment-check.sh, ci-gate-check.sh, queue-health.sh.

## Anticipated decisions

- Where to put shared function: agent-decides — in _lattice-home.sh itself (natural home)

## Decision journal

## Notes

## References

- Spec: spc-441

## Lineage

- Parent spec: **spc-441**
- Parent issue: **#441**
- Primary ticket: **tkt-447**
- Covers: **A6**
- Parallel group: G2

## Assets

## Finish

- (none yet)
