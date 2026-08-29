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
| spec | spc-187 |
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

- [ ] A script owns fix_cycles increment (finish-work Hold path + review-delivery fix loop call it)
- [ ] fix_cycles > 2 forces deep-review class; cap-exit written into workflow-fsm.md M2 table
- [ ] Validator escalates cap-breach beyond silent warn (or documents why warn is right)
- [ ] bats tests: increment; cap-exit triggers

## Approach

Today fix_cycles is template-declared but written by no core-loop script (verified: only template + validator mention it). Add bump via a small script (or stamp-pr-open --rework mode) invoked at (a) finish-work mini-review Hold (the procedural rework stamp point today) and (b) the --with-review fix loop. At >2: binder stays rework, digest class forced deep-review; workflow-fsm.md gains the explicit cap-exit transition (rework third-return → deep-review, human). Validator: decide whether >2 stays warn or becomes error with the cap-exit path defined.

## Anticipated decisions

| Decision | Disposition |
| --- | --- |
| Owner script placement | agent-decides (recommend: finish-work Hold path — the existing procedural rework stamp point) |
| Validator warn vs error at >2 | pre-resolved: warn stays, cap-exit is a class-forcing not a hard stop (review-delivery owns the class) |

## Decision journal

- 2026-08-29 — Created from spc-187 POST_SPLIT; approach pre-resolved at split time (spc-42 A5). Source: rev-20260829-160834Z F2/F5 + C6.

## Pending decisions

(none)

## Attempts

(none yet)

## Notes

- A bounded loop without a defined cap-exit is incomplete — this ticket closes the loop semantics, not just the counter.

## References

- Spec: .lattice/specs/spc-187-hard-limit-closure.md (A6)
- Law: docs/adr/007-hard-limit-scope-law.md
- Review: .lattice/reviews/rev-20260829-160834Z-workflow-fsm-hardlimit-review.md

## Lineage

- Parent spec: spc-187
- Covers: A6, A8
