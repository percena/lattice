# tkt-323 — finish-ledger writes queued→closed cancel entry for merged P

> **TL;DR:** finish-ledger writes queued→closed cancel entry for merged PRs + swallows commit_transaction IO failures
> **Kind:** bug · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug,P1 |
| github | https://github.com/percena/lattice/issues/323 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T00:00:00Z |
| updated | 2026-09-02T01:41:59Z |
| adopted | false |
| summary | finish-ledger writes queued→closed cancel entry for merged PRs + swallows commit_transaction IO failures |
| spec | none |
| paths | skills/_lattice-lib/scripts/finish-ledger.sh |
| solo_merge | yes |
| **primary_ticket** | tkt-323 (this issue) |
| worktree_bind | tkt-323-finish-ledger-ledger-entry |
| prs | pr-328 — https://github.com/percena/lattice/pull/328, pr-333 — https://github.com/percena/lattice/pull/333 |

## Acceptance

See GitHub issue #323 body.

## Approach

(to be filled at start-work)

## Anticipated decisions

(none yet)

## Notes

- Surfaced during the #321/#322 code-review (post-#270 follow-up). Confirmed real by direct code inspection.

## Lineage

- Parent issue: #323
- Primary ticket: tkt-323
- Covers: (none — standalone follow-up)

## Finish


- pr-328 merged: 2026-09-01T16:37:42Z — https://github.com/percena/lattice/pull/328 (base merge)
- issue #323 closed: 2026-09-01T16:38:09Z (reason: completed) — https://github.com/percena/lattice/issues/323
- pr-333 merged: 2026-09-02T01:41:04Z — https://github.com/percena/lattice/pull/333 (base merge)
