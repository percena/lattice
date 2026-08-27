# tkt-8-close-dependabot-prs

> **TL;DR:** After the combined v7 commit lands, close Dependabot PRs #1/#2/#3 (superseded) so the next cycle sees resolved versions + grouped config.
> **Kind:** chore · **Status:** closed · **Priority:** P2
> **Path:** spc-4 → tkt-8 → (cleanup, no PR of its own)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2, spec |
| github | https://github.com/percena/lattice/issues/8 |
| status | closed |
| adopted | false |
| summary | Close Dependabot PRs #1/#2/#3 after combined upgrade lands |
| spec | spc-4 — (path: ../../specs/spc-4-gh-actions-v7-upgrade.md) |
| covers | A7 |
| blocked_by | tkt-5 |
| parallel_group | (serial) |
| paths | (none — PR cleanup, no file change) |
| solo_merge | n/a |
| **primary_ticket** | tkt-5 (owns the ship) |
| **related_tickets** | tkt-5 |
| **worktree_bind** | `spc-4-gh-actions-v7-upgrade` |
| worktree | sibling `…/lattice.worktrees/spc-4-gh-actions-v7-upgrade/` |
| prs | (none — closes #1/#2/#3) |

## Acceptance (this slice)

- [x] **A7** Dependabot PRs #1, #2, #3 are closed (not open) once the combined upgrade is on `dev`/`main`

## Notes

- Blocked by tkt-5. Cleanup slice — close each PR with a comment pointing to the superseding commit/PR.

## Finish

- (no delivery PR — cleanup ticket; delivered by closing the superseded Dependabot PRs)
- pr-1 closed (not merged): 2026-08-01T10:30:57Z — https://github.com/percena/lattice/pull/1
- pr-2 closed (not merged): 2026-08-01T10:31:00Z — https://github.com/percena/lattice/pull/2
- pr-3 closed (not merged): 2026-08-01T10:31:03Z — https://github.com/percena/lattice/pull/3
- issue #8 closed: 2026-08-01T10:31:34Z — https://github.com/percena/lattice/issues/8
