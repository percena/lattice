# tkt-75-docs-backfill

> **TL;DR:** Audit README + getting-started skill tables against the 13 registered skills; fix CONTRIBUTING's lifecycle-six-only install example
> **Kind:** docs · **Priority:** P3
> **Path:** (ticket-only) → tkt-75 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | documentation, P3 |
| github | https://github.com/percena/lattice/issues/75 |
| status | queued |
| adopted | false |
| summary | human-facing docs catch up with the registered 13-skill reality |
| spec | none — noticed-by tkt-61 (#61, PR #67) |
| covers | tkt-61 noticed items |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | README.md, docs/getting-started.md, CONTRIBUTING.md |
| solo_merge | yes |
| **primary_ticket** | tkt-75 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-75-docs-backfill |
| worktree | sibling …/lattice.worktrees/tkt-75-docs-backfill/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] Every skill in `tools/validate-skills.sh` USER_FACING appears correctly in README's skill tables and getting-started's skill map (right tier, current one-line purpose) — or an explicit tier note covers it
- [ ] CONTRIBUTING `npx skills add` example matches the shipped skill set (full list or maintainable "all skills" form)

## Approach

Source of truth = USER_FACING in tools/validate-skills.sh (13 skills). Diff each doc table against it; add missing rows (batch-work and review-delivery likely present already — verify wording matches current SKILL.md descriptions; check side-path tier tables for review-delivery/run-e2e placement). CONTRIBUTING line ~27: replace the six-name example. Keep each table's existing voice; no restructuring.

## Anticipated decisions

- Whether getting-started's per-skill map lists side-paths individually or by tier — disposition: agent-decides (follow the table's existing structure)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Docs-only: no version bump (not bundled), CI likely path-filtered
- Do not edit skill SKILL.md descriptions to match docs — docs follow skills, never the reverse

## References

- tkt-61 final report "noticed but not touched"; `tools/validate-skills.sh` USER_FACING list

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-75** · Parallel group: **G1** · Worktree bind: `tkt-75-docs-backfill`

## Finish

- (none yet)
