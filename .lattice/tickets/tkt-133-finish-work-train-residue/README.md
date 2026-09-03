# tkt-133-finish-work-train-residue

> **TL;DR:** Remove train-retirement residue from finish-work/SKILL.md that tkt-118 missed (paths scoped flow.md only; A7 literal-grep missed Train landing)
> **Kind:** fix · **Priority:** P2
> **Path:** rev-20260827-102420Z → tkt-133 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/133 |
| status | closed |
| adopted | false |
| summary | Cleanup train-retirement residue + fix dangling §3.4 pointer in finish-work/SKILL.md |
| spec | none — ticket-only from rev-20260827-102420Z F3 |
| covers | rev F3 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/finish-work/SKILL.md |
| solo_merge | yes |
| **primary_ticket** | tkt-133 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-133-finish-work-train-residue |
| prs | pr-140 — https://github.com/percena/lattice/pull/140 |

## Acceptance (this slice)

- [x] **A1** finish-work/SKILL.md contains zero references to "train" (case-insensitive grep)
- [x] **A2** :23 pointer matches flow.md §3.4 heading (Sequential merge queue)
- [x] **A3** Conflict-resolution + checks-rollup guidance preserved (reframed, not deleted)
- [x] **A4** references/flow.md unchanged (already clean by tkt-118)

## Approach

Edit finish-work/SKILL.md: rewrite :23 "merge trains (§3.4)" → "Sequential merge queue (§3.4)"; rewrite :65,93,178,185,208,216 to drop "Train landing"/"train-transient version reds" terminology, preserving the operational guidance (file-explicit conflict resolution, gh pr checks rollup, post-merge grep) as generic "Sequential merge queue" content. ADR-005 retired the train-transient-version-red false-positive class (dev is lenient), so that concept is removed entirely.

## Anticipated decisions

- Whether to preserve the multi-PR-queue landing pattern (yes — just rename) — disposition: pre-resolved (preserve operational guidance, drop train terminology)

## References

- GitHub issue body is SoT for long prose
- Review: rev-20260827-102420Z (Finding 3)
- ADR: ADR-005 (release-train retirement)
- Prior: tkt-118 (retire-train-skill-docs, closed — missed SKILL.md)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-133 · Parallel group: G1 · Worktree bind: tkt-133-finish-work-train-residue

## Finish

- pr-140 merged: 2026-08-27 — https://github.com/percena/lattice/pull/140 (squash merge)
- issue #133 closed: 2026-08-27 — https://github.com/percena/lattice/issues/133

