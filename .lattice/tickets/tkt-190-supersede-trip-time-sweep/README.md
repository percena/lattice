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

- [x] A3: Superseding a Spec stamps its working-state child binders `deferred` + `wait_reason: spec-superseded` at supersede time
- [x] A3: Validator coupled-field rules accept the new wait_reason value
- [x] A3: finish-work land-time drift check remains as backstop
- [x] bats: sweep stamps correct binders, skips terminal ones

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
- 2026-08-29 — **Which states get stamped** (anticipated `agent-decides`): stamp `queued` + `in-progress` + `deferred` (per the launching agent's task instruction, overriding the binder's softer recommendation to flag in-progress for triage). Reasoning: the trip-time honesty principle (ADR-004 amd tkt-136/137) wins over the "agent may be mid-flight" caution — stamping `deferred` is non-destructive (it marks the binder, never kills a running process); an in-progress agent learns the work is obsolete on its next binder read. Side states (`parked`/`stuck`/`rework`) are skipped (ADR-007 sec.5b side-state guard — an external signal must not be silently overwritten); `pr-open` is skipped (a live PR is a human decision: close? re-point? — auto-deferring would orphan the PR); `closed` (terminal) and `open` (legacy) skipped. Resolution source: task instruction chain → Spec A3 → ADR-007 sec.5b.
- 2026-08-29 — **Single-commit per binder** (interpretation of "single-commit per binder, ratify.sh pattern"): one git commit per stamped binder (the ratify.sh transactional model — each binder's status flip + wait_reason set + journal entry + updated bump is one atomic commit; a crash between binders never corrupts a half-written one). Resolution source: binder Approach → ratify.sh precedent.
- 2026-08-29 — **wait_reason enum single-sourcing**: moved `STUCK_REASONS` + `DEFERRED_REASONS` into `lib/status_vocab.py` (the tkt-189 single source) and vendored the copy in the validator, extending the bats parity test to assert equality (the binder noted "extend it there; the validator vendors a parity-checked copy"). `spec-superseded` added to `DEFERRED_REASONS`. Resolution source: binder Approach → tkt-189 single-source pattern.

## Pending decisions

(none)

## Attempts

- 2026-08-29 — Implemented: `spec-supersede.sh` (sweep script), `status_vocab.py` STUCK/DEFERRED enum (single source), validator vendored copy + parity test, `spec-supersede.bats` (11 tests), morning-triage/workflow-fsm/create-spec/template docs. ci-local all-green, check-bats clean.

## Notes

## References

- Spec: `.lattice/specs/spc-186-hard-limit-closure.md` (A3)
- Review: `.lattice/reviews/rev-20260829-160834Z-workflow-fsm-hardlimit-review.md` (F8)
- Law: `docs/adr/007-hard-limit-scope-law.md`; principle origin: ADR-004 amd tkt-136 Option B

## Lineage

- Parent spec: spc-186 — https://github.com/percena/lattice/issues/187
- Origin review: rev-20260829-160834Z
- GitHub issue: #190
