# tkt-7-adr-001-policy

> **TL;DR:** Land ADR-001 codifying the SHA-pin + weekly + grouped + major-bump-validation policy.
> **Kind:** docs · **Priority:** P2
> **Path:** spc-4 → tkt-7 → (pr-… rides tkt-5 PR)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | chore, P2, spec |
| github | https://github.com/percena/lattice/issues/7 |
| status | closed |
| adopted | false |
| summary | Land ADR-001 Dependabot GitHub Actions policy + README index row |
| spec | spc-4 — (path: ../../specs/spc-4-gh-actions-v7-upgrade.md) |
| covers | A6 |
| blocked_by | (none — rides tkt-5 PR) |
| parallel_group | (serial) |
| paths | docs/adr/001-dependabot-github-actions-policy.md, docs/adr/README.md, docs/adr/template.md |
| solo_merge | no (rides tkt-5 PR) |
| **primary_ticket** | tkt-5 (owns the ship) |
| **related_tickets** | tkt-5, tkt-6 |
| **worktree_bind** | `spc-4-gh-actions-v7-upgrade` |
| worktree | sibling `…/lattice.worktrees/spc-4-gh-actions-v7-upgrade/` |
| prs | pr-9 — https://github.com/percena/lattice/pull/9 |

## Acceptance (this slice)

- [x] **A6** `docs/adr/001-dependabot-github-actions-policy.md` exists, README index row present, records SHA-pin + weekly + grouped + major-bump-validation rule

## Notes

- ADR body already drafted in this worktree (Status: Accepted). This ticket validates + lands it inside the tkt-5 PR.

## Finish

- pr-9 merged: 2026-08-01T10:29:01Z — https://github.com/percena/lattice/pull/9 (base merge)
- issue #7 closed: 2026-08-01T10:29:34Z — https://github.com/percena/lattice/issues/7
