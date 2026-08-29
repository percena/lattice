# tkt-192 — Surface pr-open aging + side-state water levels (digest + start-work)

> **Status:** queued · kind feat · priority P1 · covers spc-186 A5

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | feat | |
| priority | P1 | |
| labels | feat, P1 | |
| github | https://github.com/percena/lattice/issues/192 | |
| status | queued | |
| adopted | false | |
| summary | No staleness/aging surfacing — pr-open piles up silently if triage skipped; deferred/stuck/parked have no water-level. Eliminates silent degradation. | |
| spec | spc-186 | |
| covers | A5 | |
| blocked_by | tkt-191 | needs binder timestamps to compute age |
| parallel_group | g4 | layer 4 |
| paths | skills/review-delivery/SKILL.md, skills/review-delivery/references/, skills/start-work/SKILL.md, docs/morning-triage.md, .lattice/config.yaml | |
| solo_merge | true | one PR |
| primary_ticket | tkt-191 | |
| related_tickets | tkt-191 | blocker |
| worktree_bind | (pending start-work) | |
| worktree | (pending start-work) | |
| prs | (none) | |

## Acceptance (this slice)

- [ ] Morning digest (review-delivery) gains a "queue health" section: counts + ages of deferred/stuck/parked/pr-open beyond thresholds
- [ ] start-work entry prints a one-line water-level when side-state total > 0 (advisory, never blocks)
- [ ] Thresholds DEFAULT in .lattice/config.yaml (pr-open > 36h, side-state total > 5), tunable
- [ ] bats/tests for the threshold computation

## Approach

review-delivery digest gains a "Queue health" section computed from binder `created`/`updated` (tkt-191 dependency) + GitHub PR openedAt for pr-open age. start-work's entry banner prints a one-line water-level summary when any threshold exceeded — advisory only (DEFAULT), never a HARD block (consistent with ADR-007: this is a sensor, not a red line). Thresholds live in .lattice/config.yaml (pr-open hours, side-state counts) with sane defaults. morning-triage.md documented to read this section first.

## Anticipated decisions

- **Thresholds** — pre-resolved: config.yaml tunables; defaults pr-open > 36h, side-states > 5.
- **Surface placement** — agent-decides: digest section + start-work one-liner (recommend both).
- **pr-open age source** — agent-decides: prefer binder updated (uniform) but fall back to gh pr view openedAt when binder timestamp missing (lazy migration).

## Decision journal

- 2026-08-29: created from spc-186 POST_SPLIT (P1-5). Layer 4 behind tkt-191 (timestamps are the age-compute dependency).

## Pending decisions

(none)

## Notes

- This is a SENSOR (ADR-007 §8 escape-metric family), not a red line — advisory surfacing, never blocks.
- Blocked by tkt-191 (binder timestamps) — age computation needs created/updated.

## References

- Spec: spc-186
- Law: ADR-007
- Review: rev-20260829-160834Z
- GH issue: #192

## Lineage

- Parent spec: spc-186
- Primary ticket: tkt-192
- Related: tkt-191 (blocker)
- Covers: A5
- Blocked by: tkt-191
- Parallel group: g4
