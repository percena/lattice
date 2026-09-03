# tkt-386-noticed-backlog-drain

> **TL;DR:** Disposition all `- NOTICED:` observation lines in a rev (`ticket | one-liner | wontfix`); file the `ticket` rows; mark stale lines.
> **Kind:** chore · **Priority:** P2
> **Path:** rev-20260902-080545Z F5 → tkt-386 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/386 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:20:35Z |
| updated | 2026-09-02T12:57:10Z |
| adopted | false |
| summary | drain the NOTICED backlog: disposition all lines in a rev; file ticket rows |
| spec | (none — spawned from rev-20260902-080545Z) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G3 |
| paths | .lattice/reviews/, .lattice/tickets/*/README.md (Notes only) |
| solo_merge | yes |
| primary_ticket | tkt-386 |
| related_tickets | (none) |
| worktree_bind | tkt-386-noticed-backlog-drain |
| worktree | sibling `…/<repo>.worktrees/tkt-386-noticed-backlog-drain/` |
| prs | pr-413 — https://github.com/percena/lattice/pull/413 |

## Acceptance (this slice)

- [x] **A1** A rev records the disposition table for all NOTICED lines (none left undispositioned).
- [x] **A2** `ticket` rows filed as issues (or linked to existing issues); `wontfix` rows recorded with a reason.
- [x] **A3** NOTICED backlog count in the next lineage-metrics snapshot shows the drain.

## Approach

Grep all `.lattice/tickets/*/README.md` for `^- NOTICED:` lines. For each line, classify into `ticket` (actionable — file an issue or link an existing one), `one-liner` (noted, no action needed — record the note), or `wontfix` (explicitly not pursuing — record the reason). Write the disposition table in a `rev-` via `create-review`. Mark stale lines as `resolved-by-later-work` when evidence shows the fix landed (e.g. tkt-341 NOTICED the `conclusion` field issue — tkt-349 fixed the script, tkt-384 fixes the docs). File the `ticket` rows as new issues or cross-reference existing ones (e.g. tkt-370 NOTICED the regex — that's tkt-381 now).

**Touch-set:** `.lattice/reviews/rev-…` (new disposition rev), `.lattice/tickets/*/README.md` (Notes section only — add disposition markers, do not edit field tables).

## Anticipated decisions

- disposition format — pre-resolved (rev F5 draft): `ticket | one-liner | wontfix` table in a rev.
- stale NOTICED lines — agent-decides: mark `resolved-by-later-work` when evidence shows the fix landed (cross-reference the fixing ticket/PR).
- which lines become new tickets — agent-decides: actionable items not already covered by tkt-381..385 or an existing issue.

## Decision journal

## Pending decisions

## Attempts

## Notes

- Origin: `rev-20260902-080545Z` F5 (lineage-audit baseline, spc-369 dry run).
- NOTICED backlog: 17 binders, oldest 08-27, zero dispositions as of 2026-09-02.
- The weekly cadence step in tkt-373 (morning-triage) will keep the pile from going invisible after this drain.
- **L4 sensor data (2026-09-02):** `hotspot-metrics.sh noticed_feedback` shows 42 total NOTICED lines: 34 became_ticket (have a corresponding ticket in a rev), 8 stale_unresolved. The 8 stale lines are the specific drain scope — drain those first, then verify the count drops in the next L4 snapshot.

## References

- GitHub issue: #386
- Review: `rev-20260902-080545Z` Finding F5
- Spec: `spc-369` (review-lineage — produced the finding)
- Cadence: tkt-373 morning-triage weekly lineage-review step

## Lineage

- Parent spec: (none — spawned from review)
- Parent issue: none (ticket-only)
- Primary ticket: tkt-386
- Related / sub-tickets: (none)
- Covers: (none)
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G3
- Worktree bind: tkt-386-noticed-backlog-drain
- Child PRs: (none yet)

## Assets

## Finish


- pr-413 merged: 2026-09-02T12:54:51Z — https://github.com/percena/lattice/pull/413 (base merge)
- issue #386 closed: 2026-09-02T12:55:12Z — https://github.com/percena/lattice/issues/386

## Notes (drain summary)

- 42 NOTICED lines dispositioned in `rev-20260902-120000Z-nb.md`
- 20 resolved-by-later-work (tkt-381..384, tkt-390, tkt-402 fixed most)
- 5 ticket → filed as #409 (config.yaml docs), #410 (detect-git-branch-op), #411 (test list duplication), #412 (Spec evidence citation)
- 16 one-liner (noted, no action needed)
- 1 wontfix (chmod-000 tests fail as root — environmental)
- Backlog drained to zero undispositioned
