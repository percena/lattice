# tkt-193: Scripted fix_cycles owner + cap-exit to deep-review

## Field table

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/193 |
| status | queued |
| adopted | false |
| summary | Give fix_cycles a scripted owner and define the cap-exit: third rework return forces deep-review |
| spec | spc-186 |
| covers | A6, A8 |
| blocked_by | (none) |
| parallel_group | g1 |
| paths | skills/finish-work/**, skills/review-delivery/**, docs/workflow-fsm.md |
| solo_merge | true |
| primary_ticket | (none) |
| related_tickets | (none) |
| worktree_bind | (pending start-work) |
| worktree | (pending start-work) |
| prs | (none) |

## Acceptance (this slice)

- [x] A script owns fix_cycles increment (finish-work Hold path + review-delivery fix loop call it)
- [x] fix_cycles > 2 forces deep-review class; cap-exit written into workflow-fsm.md M2 table
- [x] Validator escalates cap-breach beyond silent warn (or documents why warn is right)
- [x] bats tests: increment; cap-exit triggers

## Approach

Today fix_cycles is template-declared but written by no core-loop script (verified: only template + validator mention it). Add bump via a small script (or stamp-pr-open --rework mode) invoked at (a) finish-work mini-review Hold (the procedural rework stamp point today) and (b) the --with-review fix loop. At >2: binder stays rework, digest class forced deep-review; workflow-fsm.md gains the explicit cap-exit transition (rework third-return → deep-review, human). Validator: decide whether >2 stays warn or becomes error with the cap-exit path defined.

## Anticipated decisions

| Decision | Disposition |
| --- | --- |
| Owner script placement | agent-decides (recommend: finish-work Hold path — the existing procedural rework stamp point) |
| Validator warn vs error at >2 | pre-resolved: warn stays, cap-exit is a class-forcing not a hard stop (review-delivery owns the class) |

## Decision journal

- 2026-08-29 — Created from spc-186 POST_SPLIT; approach pre-resolved at split time (spc-42 A5). Source: rev-20260829-160834Z F2/F5 + C6.
- 2026-08-29 — Owner-script placement: chose a dedicated `bump-fix-cycle.sh` in `_lattice-lib/scripts/` rather than extending `stamp-pr-open.sh` with a `--rework` mode (source: agent-judgment; binder Approach pre-resolved owner-script placement as agent-decides). Rationale: the bump fires at the `pr-open → rework` edge (the START of a fix cycle), while `stamp-pr-open.sh` owns the return edge `rework → pr-open` (`--force-side-state`). A dedicated script keeps each transition edge with a single scripted owner and gives the cap logic its own file; the two edges are complementary, never overlapping.
- 2026-08-29 — Cap-hit stamps `rework` (binder "stays rework"): the findings are real, so rework is the honest state, but `fix_cycles` holds at 2 and a CAP-HIT journal trace FORCES the `deep-review` triage class — no auto-retry (source: spc-186 A6 + ADR-007 §4 five-piece). The cap-exit is class-forcing, not a hard stop; pending/deep-review is an accepted production cost (ADR-007 §5b).
- 2026-08-29 — Validator stays WARNING (not error) at fix_cycles >2 (source: binder anticipated decision, pre-resolved). Documented why in the validator comment: a value >2 means a human authorized the `--extend-budget` escape (operator-adjudicated, journaled in ## Decision journal); the warning surfaces the exceeded cap for morning triage to read the escape trace, it does not block the run. The cap-exit is owned by the script + class-forcing, not the validator.
- 2026-08-29 — Idempotent cap-hit re-run: re-running `bump-fix-cycle.sh` on a `rework` binder already at cap (fix_cycles ≥2) without `--extend-budget` reprints the CAP-HIT message and mutates nothing (the deep-review forcing is re-surfaced, not re-stamped); a `rework` binder below the cap is REFUSED so the cycle must return to pr-open first (source: agent-judgment; consistency with "no auto-retry").

## Pending decisions

(none)

## Attempts

(none yet)

## Notes

- A bounded loop without a defined cap-exit is incomplete — this ticket closes the loop semantics, not just the counter.

## References

- Spec: .lattice/specs/spc-186-hard-limit-closure.md (A6)
- Law: docs/adr/007-hard-limit-scope-law.md
- Review: .lattice/reviews/rev-20260829-160834Z-workflow-fsm-hardlimit-review.md

## Lineage

- Parent spec: spc-186
- Covers: A6, A8
