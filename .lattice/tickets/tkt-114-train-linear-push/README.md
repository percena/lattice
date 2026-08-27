# tkt-114-train-linear-push

> **TL;DR:** The release-train acceptance required a divergent-blob signature that can never hold once the base itself carries the cut — every dev push after the first train merge (and every branch that merged post-cut dev back in) went red; linear/ancestor case now accepted iff the cut is byte-identical and the base is bumped relative to the released default branch
> **Kind:** fix · **Priority:** P1
> **Path:** (ticket-only) → tkt-114 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/114 |
| status | pr-open |
| adopted | false |
| summary | train_cut_shared linear/ancestor branch + origin/main released-version guard + 3 bats cases |
| spec | none — red-run disposition duty finding, first day live (dev run 33042132795) |
| covers | issue #114 A1–A3 |
| blocked_by | (none) |
| parallel_group | (hotfix — merges mid-train) |
| paths | tools/validate-plugin-versions.py, tools/tests/plugin-versions.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-114 (this issue) |
| **related_tickets** | tkt-60 (train rule origin), tkt-92 (dev CI enablement that surfaced it) |
| **worktree_bind** | tkt-114-train-linear-push |
| worktree | sibling …/lattice.worktrees/tkt-114-train-linear-push/ |
| prs | pr-115 — https://github.com/percena/lattice/pull/115 |

## Acceptance (this slice)

- [x] **A1** linear/ancestor acceptance implemented with the released-version guard (origin/main → main → strict fallback); PR-shape divergent semantics unchanged
- [x] **A2** bats: mid-train linear push accepted; post-promotion strict again; --no-train strict; existing 21 cases green
- [x] **A3** real-history repro passes (`--base-ref 148855e` prints the train acceptance line); ci-local green

## Approach

One guarded branch at the top of `train_cut_shared` for `merge_base == base_oid` (covers both dev push events and branches that merged post-cut dev in): version blobs byte-identical base↔head + worktree clean + base's manifest version > version at merge-base(base, released branch). Promotion collapses the guard back to the strict law.

## Anticipated decisions

- Released-ref resolution order — pre-resolved: `origin/main` then `main`, else strict (never guess a release point)

## Decision journal

- Ancestor condition `merge_base == base_oid and merge_base != head_oid` chosen over an event-type flag: the same geometry occurs on push events AND on PR branches that merged the post-cut base back in (observed on pr-103/pr-102 minutes after the dev reds) — one code path, both variants — chain source 1; reversible.

## Pending decisions

## Attempts

## Notes

- Found by the red-run disposition duty (finish-work DEFAULT 15) on its first live day — dev reds at 05:19Z would previously have been "cured" by the next green and never traced.

## References

- issue #114 · runs 33042132795 (dev), pr-103/pr-102 skill-quality reds · tkt-60 journal

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-114** · Parallel group: **(hotfix)** · Worktree bind: `tkt-114-train-linear-push`

## Finish
