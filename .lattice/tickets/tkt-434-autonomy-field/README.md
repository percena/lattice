# tkt-434-autonomy-field

<!-- Binder is a thin recovery card (not a second issue tracker).
     required: kind, priority, github, status, created/updated, acceptance, primary_ticket / worktree_bind when shipping
     recommended: covers, spec, summary/TL;DR, Path
     optional (parallel / C): blocked_by, merge_blocked_by, parallel_group, paths, solo_merge, related_tickets -->

> **TL;DR:** Add autonomy score field (0-4) to ticket binder template + create-tickets flow + policy
> **Kind:** feat · **Priority:** P2
> **Path:** spc-433 → tkt-434 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/434 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:00:00Z |
| updated | 2026-09-03T16:00:00Z |
| adopted | false |
| summary | Add autonomy 0-4 field to binder template + create-tickets flow + policy |
| spec | spc-433 — Vibe Coding 流程优化 (path: ../../specs/spc-433-vibe-coding-flow-optimization.md) |
| covers | A1 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/create-tickets/** |
| solo_merge | yes |
| autonomy | 4 |
| **primary_ticket** | tkt-434 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-434-autonomy-field |
| worktree | sibling |
| prs | (none) |

## Acceptance (this slice)

- [x] **A1** create-tickets 产出的 ticket binder 包含 `autonomy` 字段（0-4 整数），并有自评规则文档

## Approach

Add `autonomy` field to the binder field table in `ticket-binder.md` template, positioned adjacent to `solo_merge` and `parallel_group` (execution-disposition peers). Update `policy.md` §Independence gates to declare the field. Update `flow.md` §2.2 (anticipated-decisions scan) to set autonomy during split, and §3.5 (binder fill) to include it in the authoring step. Add a scoring rubric reference (0=Day-Interactive through 4=full-auto-mergeable).

Touch-set:
- `skills/create-tickets/references/templates/ticket-binder.md` — add `autonomy` row to field table
- `skills/create-tickets/references/policy.md` — declare field in independence gates + self-contained tickets
- `skills/create-tickets/references/flow.md` §2.2/§3.5 — set autonomy at split time
- `skills/_lattice-lib/references/` — add autonomy scoring rubric to decision-policy.md or new reference

## Anticipated decisions

- autonomy field values: 0-4 integers (0-indexed) — disposition: pre-resolved(spec decision 1)
- field table position: adjacent to solo_merge/parallel_group — disposition: pre-resolved(dry-run)
- scoring rubric location: decision-policy.md or new reference — disposition: agent-decides (reversible doc placement)
- whether validator enforces allowed values: — disposition: must-ask (cross-contract: validator is _lattice-lib, not create-tickets)

## Decision journal

(append-only during execution)

## Pending decisions

- Should the validator (validate-lattice-artifacts.py) enforce autonomy field values 0-4? Needs cross-skill coordination with _lattice-lib.

## Attempts

(none yet)

## Notes

Foundation ticket — T2, T3, T4 all depend on this field existing.

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-433` (path above)
- ADR: ADR-006 (worktree discipline — autonomy governs execution mode)
- Worktree policy: one tree ↔ one PR

## Lineage

- Parent spec: **spc-433**
- Parent issue: **#433**
- Primary ticket: **tkt-434**
- Related / sub-tickets: tkt-435, tkt-436, tkt-437 (all blocked_by this)
- Covers: **A1**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: (serial — foundation)
- Worktree bind: tkt-434-autonomy-field
- Child PRs: (none yet)

## Assets

(none)

## Finish

- (none yet)
