# tkt-82-zh-readme-sync

> **TL;DR:** Port tkt-75's English README updates (13-skill tables, corrected packaging claims) into README.zh-CN.md
> **Kind:** docs · **Priority:** P3
> **Path:** (ticket-only) → tkt-82 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | documentation, P3 |
| github | https://github.com/percena/lattice/issues/82 |
| status | queued |
| adopted | false |
| summary | zh README catches up with the English README's current skill reality |
| spec | none — digest finding (rev-20260826-172600Z F7), noticed-by tkt-75 |
| covers | digest F7 |
| blocked_by | #75 (port its merged English wording, not a moving target) |
| parallel_group | G1 (parallel) |
| paths | README.zh-CN.md |
| solo_merge | yes |
| **primary_ticket** | tkt-82 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-82-zh-readme-sync |
| worktree | sibling …/lattice.worktrees/tkt-82-zh-readme-sync/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] README.zh-CN tables/claims enumerate the same skills as the English README with equivalent wording intent; existing zh voice/structure preserved

## Approach

Diff README.md (post-#77) against README.zh-CN.md section by section; port the skill-table rows, tier notes, and corrected packaging claims; translate faithfully rather than restructure. Verify by listing both files' table rows side by side in the PR body.

## Anticipated decisions

- Terminology for new concepts (e.g. 链路审查 for chain review) — disposition: agent-decides (follow the zh doc's existing glossary habits; journal choices)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Docs-only: no version bump; CI path-filtered

## References

- Digest: `rev-20260826-172600Z` Finding 7 · tkt-75 audit table (PR #77 body)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-82** · Parallel group: **G1** · Worktree bind: `tkt-82-zh-readme-sync`

## Finish

- (none yet)
