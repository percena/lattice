# tkt-444-macos-ci-matrix

> **TL;DR:** Add macOS runner to CI test matrix for shell portability coverage
> **Kind:** chore · **Priority:** P2
> **Path:** spc-441 → tkt-444 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/444 |
| status | queued |
| fix_cycles | 0 |
| created | 2026-09-03T15:43:52Z |
| updated | 2026-09-03T15:43:52Z |
| adopted | false |
| summary | Add macOS runner to bats CI workflows |
| spec | spc-441 — project-wide hardening sweep (path: ../../specs/spc-441-hardening-sweep.md) |
| covers | A3 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | .github/workflows/lattice-scripts.yml, .github/workflows/plugin-hooks.yml |
| solo_merge | yes |
| autonomy | 3 |
| primary_ticket | tkt-444 |
| related_tickets | (none) |

## Acceptance (this slice)

- [ ] **A3** lattice-scripts.yml and plugin-hooks.yml run bats on both ubuntu-latest and macos-latest; all tests pass

## Approach

Add `strategy.matrix.os: [ubuntu-latest, macos-latest]` + `runs-on: ${{ matrix.os }}`. Bats builds from source (1.13.0) — should work on macOS. May need brew install for jq/python3.

## Anticipated decisions

- Which workflows get macOS: pre-resolved — lattice-scripts.yml + plugin-hooks.yml (the bats runners)

## Decision journal

## Notes

May surface BSD vs GNU portability issues that need follow-up tickets.

## References

- Spec: spc-441

## Lineage

- Parent spec: **spc-441**
- Parent issue: **#441**
- Primary ticket: **tkt-444**
- Covers: **A3**
- Parallel group: G1

## Assets

## Finish

- (none yet)
