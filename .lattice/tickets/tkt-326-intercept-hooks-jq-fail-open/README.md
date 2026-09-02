# tkt-326 — jq on empty/partial output triggers set -e block (not fail-o

> **TL;DR:** jq on empty/partial output triggers set -e block (not fail-open) in both intercept hooks
> **Kind:** bug · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug,P2 |
| github | https://github.com/percena/lattice/issues/326 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T00:00:00Z |
| updated | 2026-09-02T00:00:00Z |
| adopted | false |
| summary | jq on empty/partial output triggers set -e block (not fail-open) in both intercept hooks |
| spec | none |
| paths | plugins/lattice/hooks/intercept-shippable-write.sh, plugins/lattice/hooks/intercept-git-branch-create.sh |
| solo_merge | yes |
| **primary_ticket** | tkt-326 (this issue) |
| worktree_bind | tkt-326-intercept-hooks-jq-fail-open |
| prs | (none…) · pr-331 — https://github.com/percena/lattice/pull/331 |

## Acceptance

See GitHub issue #326 body.

## Approach

(to be filled at start-work)

## Anticipated decisions

(none yet)

## Notes

- Surfaced during the #321/#322 code-review (post-#270 follow-up). Confirmed real by direct code inspection.

## Lineage

- Parent issue: #326
- Primary ticket: tkt-326
- Covers: (none — standalone follow-up)

## Finish


- pr-331 merged: 2026-09-02T01:30:57Z — https://github.com/percena/lattice/pull/331 (base merge)
- issue #326 closed: 2026-09-02T01:31:08Z — https://github.com/percena/lattice/issues/326
