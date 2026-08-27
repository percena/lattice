# tkt-6-dependabot-groups-block

> **TL;DR:** Add a `groups:` block to `dependabot.yml` so all github-actions bumps group into one PR per cycle.
> **Kind:** chore · **Priority:** P2
> **Path:** spc-4 → tkt-6 → (pr-… rides tkt-5 PR)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2, spec |
| github | https://github.com/percena/lattice/issues/6 |
| status | closed |
| adopted | false |
| summary | Add Dependabot github-actions groups block (patterns: ["*"]) |
| spec | spc-4 — (path: ../../specs/spc-4-gh-actions-v7-upgrade.md) |
| covers | A5 |
| blocked_by | (none — rides tkt-5 PR) |
| parallel_group | (serial) |
| paths | .github/dependabot.yml |
| solo_merge | no (rides tkt-5 PR) |
| **primary_ticket** | tkt-5 (owns the ship) |
| **related_tickets** | tkt-5, tkt-7 |
| **worktree_bind** | `spc-4-gh-actions-v7-upgrade` |
| worktree | sibling `…/lattice.worktrees/spc-4-gh-actions-v7-upgrade/` |
| prs | pr-9 — https://github.com/percena/lattice/pull/9 |

## Acceptance (this slice)

- [x] **A5** `.github/dependabot.yml` contains a `groups:` block grouping `github-actions` with `patterns: ["*"]`

## Notes

- Implements ADR-001 Decision 2. No standalone PR — lands inside the tkt-5 combined PR.

## Finish

- pr-9 merged: 2026-08-01T10:29:01Z — https://github.com/percena/lattice/pull/9 (base merge)
- issue #6 closed: 2026-08-01T10:29:30Z — https://github.com/percena/lattice/issues/6
