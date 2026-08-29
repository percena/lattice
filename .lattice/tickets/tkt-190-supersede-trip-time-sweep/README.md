# tkt-190 — Spec supersede trip-time sweep stamps child binders deferred

> **Status:** queued · kind feat · priority P0 · covers spc-186 A3

## Field table

| field | value |
| --- | --- |
| kind | feat |
| priority | P0 |
| labels | feat, P0 |
| github | https://github.com/percena/lattice/issues/190 |
| status | queued |
| adopted | false |
| summary | Superseding a Spec stamps its still-active child binders deferred + spec-superseded at supersede time |
| spec | spc-186 |
| covers | A3 |
| blocked_by | tkt-189 |
| parallel_group | g2 |
| paths | skills/create-spec/**, skills/_lattice-lib/scripts/, tools/validate-lattice-artifacts.py, docs/morning-triage.md |
| solo_merge | true |
| primary_ticket | true |
| related_tickets | tkt-189 |
| worktree_bind | (pending start-work) |
| prs | (none) |

## Acceptance (this slice)

- [ ] A3: Superseding a Spec stamps its working-state child binders `deferred` + `wait_reason: spec-superseded` at supersede time
- [ ] A3: Validator coupled-field rules accept the new wait_reason value
- [ ] A3: finish-work land-time drift check remains as backstop
- [ ] bats: sweep stamps correct binders, skips terminal ones

## Approach

New script (e.g. `_lattice-lib/scripts/spec-supersede.sh`) invoked from create-spec's supersede path: read superseded Spec's `tickets:` list, for each child binder in a working state stamp `deferred` + `wait_reason: spec-superseded` (single-commit per binder, ratify.sh pattern); terminal binders untouched. Validator: extend deferred wait_reason enum with `spec-superseded` (lands on top of tkt-189's single-sourced vocabulary — hence blocked_by). finish-work keeps its land-time Spec drift check as backstop. morning-triage.md gains the disposition line for spec-superseded deferred tickets (re-plan under superseding Spec or cancel).

## Anticipated decisions

| Decision | Disposition | Notes |
| --- | --- | --- |
| wait_reason value name | pre-resolved | `spec-superseded` |
| Which states get stamped | agent-decides | recommend queued+deferred; in-progress flagged for triage instead (agent may be mid-flight) |
| blocked_by tkt-189 | pre-resolved | wait_reason enum lives in the single-sourced vocabulary after tkt-189 |

## Decision journal

- 2026-08-29 — Created from spc-186 POST_SPLIT; approach pre-resolved at split time. Resolution source: rev-20260829-160834Z + ADR-007.

## Pending decisions

(none)

## Attempts

(none yet)

## Notes

## References

- Spec: `.lattice/specs/spc-186-hard-limit-closure.md` (A3)
- Review: `.lattice/reviews/rev-20260829-160834Z-workflow-fsm-hardlimit-review.md` (F8)
- Law: `docs/adr/007-hard-limit-scope-law.md`; principle origin: ADR-004 amd tkt-136 Option B

## Lineage

- Parent spec: spc-186 — https://github.com/percena/lattice/issues/187
- Origin review: rev-20260829-160834Z
- GitHub issue: #190
