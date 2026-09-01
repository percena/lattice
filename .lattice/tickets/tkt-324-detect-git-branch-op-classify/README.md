# tkt-324 — git branch -f force-create bypass

> **TL;DR:** git branch -f force-create bypass + git checkout <treeish> -- <path> file-restore misclassified as switch
> **Kind:** bug · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug,P1 |
| github | https://github.com/percena/lattice/issues/324 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T00:00:00Z |
| updated | 2026-09-01T16:47:25Z |
| adopted | false |
| summary | git branch -f force-create bypass + git checkout <treeish> -- <path> file-restore misclassified as switch |
| spec | none |
| paths | plugins/lattice/scripts/detect-git-branch-op.py |
| solo_merge | yes |
| **primary_ticket** | tkt-324 (this issue) |
| worktree_bind | tkt-324-detect-git-branch-op-classify |
| prs | pr-329 — https://github.com/percena/lattice/pull/329 |

## Acceptance

See GitHub issue #324 body.

## Approach

(to be filled at start-work)

## Anticipated decisions

(none yet)

## Notes

- Surfaced during the #321/#322 code-review (post-#270 follow-up). Confirmed real by direct code inspection.

## Lineage

- Parent issue: #324
- Primary ticket: tkt-324
- Covers: (none — standalone follow-up)

## Finish


- pr-329 merged: 2026-09-01T16:46:40Z — https://github.com/percena/lattice/pull/329 (base merge)
- issue #324 closed: 2026-09-01T16:47:08Z (reason: completed) — https://github.com/percena/lattice/issues/324
