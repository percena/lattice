# tkt-389-method-template-l4

> **TL;DR:** method.md L4 synthesis section (root-cause + curve-bending + structural-vs-tactical) + template ## Weak-spot topology + ## Optimization recommendations.
> **Kind:** docs · **Priority:** P2
> **Path:** spc-387 → tkt-389 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | documentation, P2 |
| github | https://github.com/percena/lattice/issues/389 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:31:00Z |
| updated | 2026-09-02T09:47:08Z |
| adopted | false |
| summary | method.md L4 extension + template topology/recommendations (spc-387 A2+A3) |
| spec | spc-387 — weak-spot topology + optimization recommendations |
| covers | A2, A3 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G2 |
| paths | skills/review-lineage/references/method.md, skills/review-lineage/references/templates/lineage-audit.md |
| solo_merge | yes |
| primary_ticket | tkt-389 |
| related_tickets | (none) |
| worktree_bind | tkt-389-method-template-l4 |
| worktree | sibling `…/<repo>.worktrees/tkt-389-method-template-l4/` |
| prs | pr-390 — https://github.com/percena/lattice/pull/390 |

## Acceptance (this slice)

- [x] **A2** method.md gains ## L4 synthesis section: root-cause hypothesis (4 patterns), curve-bending formula, structural-vs-tactical diagnosis.
- [x] **A3** lineage-audit.md template gains ## Weak-spot topology + ## Optimization recommendations after ## Findings. Bounded: ≤5 hotspots + ≤3 recommendations.

## Approach

Append L4 section to method.md (root-cause patterns: multi-writer disagreement, decided-but-unimplemented ADR, format-drift escape, environment-dependence; curve-bending formula: impact = fix_commit_count × fix_class_diversity × cross_audit_recurrence_count × structural_depth; structural-vs-tactical: structural = references decided-but-unimplemented ADR). Add two sections to lineage-audit.md template after ## Findings.

## Decision journal

- 2026-09-02T09:47:08Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #390) [WARN — signal logged, not silently lost]

## Notes

- Origin: spc-387 (review-lineage L4 weak-spot topology).
- Spec primary: #387 (GH sub-issue linked).

## Finish

- (none yet)
