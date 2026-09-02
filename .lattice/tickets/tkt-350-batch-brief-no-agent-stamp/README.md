# tkt-350-batch-brief-no-agent-stamp

> **TL;DR:** batch-work spawn brief still instructs agents to stamp in-progress by prose; the bind stamps it since tkt-339 and a second commit is refused.
> **Kind:** bug · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug,P2 |
| github | https://github.com/percena/lattice/issues/350 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T03:33:16Z |
| updated | 2026-09-02T04:19:01Z |
| adopted | false |
| summary | batch-work spawn brief still instructs agents to stamp in-progress by prose; the bind stamps it since tkt-339 and a second commit is refused. |
| spec | none |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-350 (this issue) |
| worktree_bind | tkt-350-batch-brief-no-agent-stamp |
| prs | (none) |

## Acceptance

See GitHub issue #350 body (A1).

## Approach

1. SKILL.md spawn-brief contract + step 7 and flow.md §SPAWN LAYER: replace 'stamp in-progress on start' with 'the bind stamps in-progress; after-pr-open.sh / PostToolUse hook stamp pr-open — agents do not edit status'. 2. docs-truth bats asserting the instruction is gone.

## Anticipated decisions

(none — S-class)

## Decision journal

## Notes

- Surfaced during the spc-337 delivery (finish-work runs on PRs #343–#348; reviewer finding on PR #348). Follow-up per preferences.md "Review-findings → tickets".

## Lineage

- Parent issue: #350 (ticket-only, no Spec)
- Primary ticket: tkt-350
- Refs: spc-337, ADR-012

## Finish

- (none yet)
