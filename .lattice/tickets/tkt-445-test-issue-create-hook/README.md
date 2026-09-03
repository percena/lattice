# tkt-445-test-issue-create-hook

> **TL;DR:** Add bats test for the only untested hook — intercept-gh-issue-create.sh
> **Kind:** test · **Priority:** P2
> **Path:** spc-441 → tkt-445 → (pr-…)

| Field | Value |
| --- | --- |
| kind | test |
| priority | P2 |
| labels | test, P2 |
| github | https://github.com/percena/lattice/issues/445 |
| status | queued |
| fix_cycles | 0 |
| created | 2026-09-03T15:44:31Z |
| updated | 2026-09-03T15:44:31Z |
| adopted | false |
| summary | Test intercept-gh-issue-create hook covering block/allow/advisory paths |
| spec | spc-441 — project-wide hardening sweep (path: ../../specs/spc-441-hardening-sweep.md) |
| covers | A4 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | plugins/lattice/hooks/intercept-gh-issue-create.sh, plugins/lattice/scripts/tests/ |
| solo_merge | yes |
| autonomy | 4 |
| primary_ticket | tkt-445 |
| related_tickets | (none) |

## Acceptance (this slice)

- [x] **A4** intercept-gh-issue-create.bats exists with tests covering block, allow, and advisory paths

## Approach

Follow pattern from intercept-gh-pr-create.bats: stub gh via PATH injection, set up skill markers, test exit codes and output messages. Touch-set: plugins/lattice/scripts/tests/intercept-gh-issue-create.bats.

## Anticipated decisions

- (none — follow existing test patterns)

## Decision journal

## Notes

## References

- Spec: spc-441
- Pattern: plugins/lattice/scripts/tests/intercept-gh-pr-create.bats

## Lineage

- Parent spec: **spc-441**
- Parent issue: **#441**
- Primary ticket: **tkt-445**
- Covers: **A4**
- Parallel group: G1

## Assets

## Finish

- (none yet)
