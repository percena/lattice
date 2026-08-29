# tkt-188 — Machine-enforce the batch merge gate (marker lifecycle + human-adjudicated escape)

> **Status:** in-progress · kind feat · priority P0 · covers spc-186 A1,A8

## Field table

| field | value |
| --- | --- |
| kind | feat |
| priority | P0 |
| labels | feat, P0 |
| github | https://github.com/percena/lattice/issues/188 |
| status | pr-open |
| adopted | false |
| summary | Make the "night states never reach merged" invariant machine-checked: a merge hook blocks bare `gh pr merge` while the batch-work marker is present, with a human-adjudicated escape (ADR-007) |
| spec | spc-186 |
| covers | A1, A8 |
| blocked_by | (none) |
| parallel_group | g1 |
| paths | plugins/lattice/hooks/**, skills/finish-work/**, skills/batch-work/** |
| solo_merge | true |
| primary_ticket | true |
| related_tickets | tkt-189, tkt-190, tkt-193 |
| worktree_bind | (worktree) tkt-188-batch-merge-gate |
| prs | pr-197 — https://github.com/percena/lattice/pull/197 |

## Acceptance (this slice)

- [x] A1: Merge path refuses while an active `.batch-work-active` marker exists (fail-closed hook check, not prose)
- [x] A1: Human-adjudicated escape per ADR-007 (operator removes marker, or sets `.batch-merge-authorized` with structured reason; trace in binder journal)
- [x] A1: Marker creation/removal/scope semantics consistent across `batch-work`/`finish-work` docs and code (single gate point at repo MAIN `.lattice/`, not per-worktree; retire per-worktree copies)
- [x] A8: five-piece contract for the guard (check / message / escape / trace / metric)
- [x] bats: marker present → blocked; marker absent → allowed; escape flag honored

## Approach

The invariant "night states never reach merged" was prose-only — finish-work SKILL.md:60/84/106 stated the gate but no script/hook checked `.lattice/.batch-work-active`, and cleanup-workspace.sh had zero references; the removal wording was self-contradictory ("remove before merge" vs "remove after merge"). This ticket closes that:

1. **Guard (check + message):** extend `plugins/lattice/hooks/lib/intercept-gh-pr-common.sh` so a bare `gh pr merge` while the marker is present is blocked fail-closed (exit 2 strict; advisory JSON otherwise). New shared lib `plugins/lattice/hooks/lib/batch-merge-gate.sh` resolves the repo MAIN clone `.lattice/` (single gate point — NOT per-worktree) and checks the marker. Verb-scoped to merge (create unaffected). Fails OPEN when the lattice home cannot be resolved.
2. **Escape (ADR-007 §5b/§5c):** operator removes the marker, OR sets `.batch-merge-authorized` with a structured reason. No agent self-adjudication; unapproved crossings invalid (redo/rollback).
3. **Trace:** finish-work script `skills/finish-work/scripts/batch-merge-gate.sh` removes the marker BEFORE merge (after human ack) and emits a structured `## Decision journal` line (rule_id, reason, authorizer, timestamp). NOT after merge — fixes the C3 wording contradiction.
4. **Metric:** escape counts surface in the morning digest (ADR-007 §8) — wiring deferred to the digest ticket; the trace line carries rule_id so the digest can count.
5. **Docs:** fix finish-work SKILL.md (lines 60/84/106) + batch-work SKILL.md/flow.md — marker at MAIN clone, removed before merge, single gate point; retire per-worktree copies.

## Anticipated decisions

| Decision | Disposition | Notes |
| --- | --- | --- |
| Marker location: MAIN `.lattice/` vs per-worktree | pre-resolved (spc-186 A1) | single gate point at MAIN; retire per-worktree copies — one gate the human controls |
| Removal timing: before vs after merge | pre-resolved (spc-186 A1 / ADR-007 §5c) | BEFORE merge (after human ack); the merge hook enforces fail-closed — fixes C3 contradiction |
| Escape mechanism: remove marker vs authorized-merge flag | agent-decides (implemented both) | remove = batch done; flag = keep batch active, merge with trace |
| Root resolution: env override vs git | agent-decides | LATTICE_BATCH_GATE_HOME override (tests/manual) else git rev-parse --git-common-dir → MAIN .lattice; fail-open on unresolved |

## Decision journal

- 2026-08-29 — Created binder; tkt-188 binder was missing from the spc-186 POST_SPLIT set (setup gap). Reversible + ticket-local → self-decide + journal. Resolution source: decision-policy §reversible+ticket-local. Approach derived from the spc-186 A1 acceptance + ADR-007 five-piece contract.
- 2026-08-29 — GitHub issue #188 title/body is "Spec supersede trip-time sweep" (A3, duplicate of #190), NOT batch-merge-gate (A1). No dedicated A1 issue exists. Used "Refs #188" (not "Fixes #188") in the PR body to avoid incorrectly auto-closing the A3 issue on merge — reversible (operator can edit PR body + reconcile #188's title/body). Resolution source: decision-policy §cross-contract + ADR-007 (unapproved durable-state crossings invalid).

## Pending decisions

(none)

## Attempts

(none yet)

## Notes

- The spec spc-186 and ADR-007 ship on dev under `.lattice-worktrees/spc-186-hard-limit-closure/` (committed at e0f724e). The canonical cite path `.lattice/specs/spc-186-hard-limit-closure.md` is used for consistency with sibling binders; the operator may reconcile the spec's committed location later.

## References

- Spec: `.lattice/specs/spc-186-hard-limit-closure.md` (A1, A8)
- Law: `docs/adr/007-hard-limit-scope-law.md` — boundary law + escape adjudication (§4 five-piece, §5b/§5c human-adjudicated)
- Review: `rev-20260829-160834Z` (F- findings — merge gate prose-only)
- Guard site: `plugins/lattice/hooks/lib/intercept-gh-pr-common.sh` (merge verb path)
- Marker lifecycle: `skills/finish-work/scripts/batch-merge-gate.sh`, `skills/batch-work/SKILL.md`

## Lineage

- Parent spec: spc-186 — https://github.com/percena/lattice/issues/187
- Origin review: rev-20260829-160834Z
- GitHub issue: #188
