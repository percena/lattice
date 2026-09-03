# tkt-388-hotspot-metrics-sensor

> **TL;DR:** Implement hotspot-metrics.sh sensor (clusters, fix-class, genealogy, cross-audit, NOTICED feedback) + bats tests + dry run on this repo.
> **Kind:** feat · **Priority:** P2
> **Path:** spc-387 → tkt-388 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/388 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:31:00Z |
| updated | 2026-09-02T09:57:53Z |
| adopted | false |
| summary | hotspot-metrics.sh sensor + bats (spc-387 A1+A4) |
| spec | spc-387 — weak-spot topology + optimization recommendations |
| covers | A1, A4 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/review-lineage/scripts/hotspot-metrics.sh, scripts/lib/hotspot_metrics.py, scripts/tests/hotspot-metrics.bats, scripts/tests/fixtures/hotspot/ |
| solo_merge | yes |
| primary_ticket | tkt-388 |
| related_tickets | (none) |
| worktree_bind | tkt-388-hotspot-metrics-sensor |
| worktree | sibling `…/<repo>.worktrees/tkt-388-hotspot-metrics-sensor/` |
| prs | pr-390 — https://github.com/percena/lattice/pull/390 |

## Acceptance (this slice)

- [x] **A1** hotspot-metrics.sh computes hotspot_clusters, fix_class_histogram, ticket_genealogy, cross_audit_recurrence, noticed_feedback per spc-387 A1 contract.
- [x] **A4** Bats: planted-drift tests + dry run on this repo (terminal-stamp = #1, 54% fix share, ≥3 cross-audit revs, status-flip > 0).

## Approach

Python lib `hotspot_metrics.py` (parallel to `lineage_metrics.py`) + bash wrapper `hotspot-metrics.sh` (parallel to `lineage-metrics.sh`). Reuses `_import_lattice_lib()` pattern. Computes:
1. hotspot_clusters: git log fix() commits → --name-only → group by path → dedup by hash
2. fix_class_histogram: subject regex classification
3. ticket_genealogy: grep revs for Proposed-tickets tables + binders for fix_cycles
4. cross_audit_recurrence: grep rev ### F headings for finding-class keywords
5. noticed_feedback: count NOTICED → became_ticket (in rev Proposed-tickets)

## Decision journal

- 2026-09-02T09:47:06Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #390) [WARN — signal logged, not silently lost]

## Notes

- Origin: spc-387 (review-lineage L4 weak-spot topology).
- Spec primary: #387 (GH sub-issue linked).

## Finish


- pr-390 merged: 2026-09-02T09:56:14Z — https://github.com/percena/lattice/pull/390 (base merge)
- issue #388 closed: 2026-09-02T09:56:53Z (reason: completed) — https://github.com/percena/lattice/issues/388
