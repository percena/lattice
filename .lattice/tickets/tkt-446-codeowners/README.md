# tkt-446-codeowners

> **TL;DR:** Add CODEOWNERS for hooks, workflows, and tools directories
> **Kind:** chore · **Priority:** P2
> **Path:** spc-441 → tkt-446 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/446 |
| status | closed |
| fix_cycles | 0 |
| created | 2026-09-03T15:44:31Z |
| updated | 2026-09-03T16:52:04Z |
| adopted | false |
| summary | Add .github/CODEOWNERS for security-sensitive paths |
| spec | spc-441 — project-wide hardening sweep (path: ../../specs/spc-441-hardening-sweep.md) |
| covers | A5 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | .github/CODEOWNERS |
| solo_merge | yes |
| autonomy | 4 |
| primary_ticket | tkt-446 |
| related_tickets | (none) |

## Acceptance (this slice)

- [x] **A5** .github/CODEOWNERS exists with entries for plugins/lattice/hooks/, .github/workflows/, and tools/

## Approach

Create .github/CODEOWNERS with maintainer entries for the three directories. Touch-set: .github/CODEOWNERS.

## Anticipated decisions

- (none)

## Decision journal

## Notes

## References

- Spec: spc-441

## Lineage

- Parent spec: **spc-441**
- Parent issue: **#441**
- Primary ticket: **tkt-446**
- Covers: **A5**
- Parallel group: G1

## Assets

## Finish


- pr-454 merged: 2026-09-03T16:49:22Z — https://github.com/percena/lattice/pull/454 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #446 closed: 2026-09-03T16:50:10Z (reason: completed) — https://github.com/percena/lattice/issues/446
