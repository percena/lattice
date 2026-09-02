# tkt-412-spec-acceptance-evidence-convention

> **TL;DR:** 14 of 16 done Specs have checked A* items citing no test/PR/ticket evidence. The `spec-done-acceptance-cites-evidence` probe is stricter than the current Spec convention (evidence lives in binders/PR bodies, not Spec lines). Adjust the probe/convention so the signal reflects reality, not false noise.
> **Kind:** enhancement · **Priority:** P3
> **Path:** tkt-412 → (pr-…)

| Field | Value |
| --- | --- |
| kind | enhancement |
| priority | P3 |
| labels | enhancement, P3 |
| github | https://github.com/percena/lattice/issues/412 |
| status | in-progress |
| adopted | true |
| summary | align the spec-done-acceptance-cites-evidence probe with the binder/PR evidence convention (no spec content edits) |
| spec | none |
| covers | A1 |
| blocked_by | none |
| parallel_group | (serial — batch with tkt-409/410/411) |
| paths | skills/review-lineage/references/probes.md, skills/review-lineage/scripts/** (probe def) |
| solo_merge | no (batch PR) |
| **primary_ticket** | tkt-412 |
| **related_tickets** | tkt-409, tkt-410, tkt-411 (NOTICED-drain batch) |
| **worktree_bind** | tkt-409-noticed-drain-fixes |
| worktree | sibling …/lattice.worktrees/tkt-409-noticed-drain-fixes/ |
| prs | pending |

## Acceptance (this slice)

- [x] **A1** The `spec-done-acceptance-cites-evidence` probe no longer flags done Specs whose A* items have evidence in their bound ticket/PR rather than inline on the Spec line — either by (a) lowering severity from `low` to `info`/silent with a convention note, (b) adjusting the matcher to accept a binder/PR cross-reference at the Spec acceptance-section level, or (c) documenting the convention so the probe is understood as an opt-in strict check. No `.lattice/specs/**` content edits.

## Approach

The probe (probes.md:46) already self-documents: "Stricter than the current Spec convention (evidence conventionally lives in binders / PR bodies, not on the Spec line), hence severity low: an audit signal, not a gate." The fix is to make the probe reflect the convention: downgrade to `info` severity (or gate it behind an explicit `--strict-evidence` flag) and clarify the probe description so the morning digest stops surfacing it as a defect. Confirm the probe implementation location (review-lineage scripts) and adjust consistently. Do NOT edit spec content — the evidence is in binders/PRs by design.

## Decision journal

## Pending decisions

## Attempts

## Notes

- NOTICED in tkt-371. Filed by tkt-386 NOTICED backlog drain. rev-20260902-015425Z F6 measured 84 items.
- Operator-confirmed approach (2026-09-02): adjust probe/convention, no spec content edits.

## References

- skills/review-lineage/references/probes.md:46 · rev-20260902-015425Z F6 · ADR-007 §3 (decidability)

## Lineage

- Parent spec: none · Primary ticket: tkt-412 · Parallel group: (serial NOTICED-drain batch) · Worktree bind: `tkt-409-noticed-drain-fixes`

## Finish
