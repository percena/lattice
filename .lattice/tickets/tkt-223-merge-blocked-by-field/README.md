# tkt-223-merge-blocked-by-field

<!-- Binder is a thin recovery card (not a second issue tracker).
     required: kind, priority, github, status, created/updated, acceptance, primary_ticket / worktree_bind when shipping
     recommended: covers, spec, summary/TL;DR, Path
     optional (parallel / C): blocked_by, parallel_group, paths, solo_merge, related_tickets, merge_blocked_by -->

> **TL;DR:** Add `merge_blocked_by` ticket-binder field + policy doc for merge-order DAG (fallback `blocked_by`).
> **Kind:** feat · **Priority:** P2 <!-- status lives in the field table -->
> **Path:** spc-220 → tkt-223 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/223 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-30T00:00:00Z |
| updated | 2026-08-29T16:50:58Z |
| adopted | false |
| summary | Add merge_blocked_by binder field + create-tickets policy (merge-order DAG, fallback blocked_by) |
| spec | spc-220 — finish-work multi-PR DAG-aware merge (path: ../../specs/spc-220-batch-finish-dag.md) |
| covers | A1 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/create-tickets/references/templates/ticket-binder.md, skills/create-tickets/references/policy.md |
| solo_merge | yes |
| **primary_ticket** | tkt-223 (this issue) — owner of the ship when this tree has one PR |
| **related_tickets** | tkt-224 (same one-PR ship: finish-work multi-PR mode consumes this field) |
| **worktree_bind** | `spc-220-batch-finish-dag` |
| worktree | sibling `…/lattice.worktrees/spc-220-batch-finish-dag/` |
| prs | pr-230 — https://github.com/percena/lattice/pull/230 |

## Acceptance (this slice)

- [ ] **A1** `merge_blocked_by` field exists in `skills/create-tickets/references/templates/ticket-binder.md` field table (after `blocked_by`) + Lineage section + optional-row comment, and is documented in `skills/create-tickets/references/policy.md` as merge-order (not work-start) with fallback-to-`blocked_by` noted.

## Approach

- Add a `merge_blocked_by` row to the binder field table (after `blocked_by`): `merge_blocked_by | (none \| #N) | merge-order DAG — #N must MERGE before this ticket's PR (distinct from blocked_by = work-start order; usually the same but governs landing order for stacked PRs / logical deps). Consumed by finish-work multi-PR mode; falls back to blocked_by when absent`.
- Add `Merge blocked by:` line to the Lineage section.
- List `merge_blocked_by` in the top optional-row comment.
- Add a short `merge_blocked_by` subsection in `policy.md`.

## Anticipated decisions

- Field placement (after `blocked_by`) — disposition: pre-resolved (mirrors `blocked_by`).

## Decision journal

<!-- Append-only during execution. -->
- 2026-08-29T16:50:58Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #230) [WARN — signal logged, not silently lost]

## Pending decisions

<!-- -->

## Attempts

<!-- -->

## Notes

- Ships in one PR with tkt-224 (finish-work multi-PR mode). primary_ticket = tkt-224 for the combined PR; this ticket is the related/folded slice covering A1.

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-220` (path above) — do not duplicate full Spec here
- Worktree policy: one tree ↔ one PR; spc|tkt open binds

## Lineage

- Parent spec: **spc-220**
- Parent issue: **#220**
- Primary ticket: **tkt-223**
- Related / sub-tickets: **tkt-224**
- Covers: **A1**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: (serial)
- Worktree bind: spc-220-batch-finish-dag
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
