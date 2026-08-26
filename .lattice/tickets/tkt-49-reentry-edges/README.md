# tkt-49-reentry-edges

> **TL;DR:** Close the FSM dead ends — rework re-entry for returned PRs, parked→queued wake-up on ratify, rebase-invalidated verdict re-review in finish-work, stuck triage exits
> **Kind:** feat · **Status:** pr-open · **Priority:** P2
> **Path:** spc-42 → tkt-49 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/49 |
| status | pr-open |
| adopted | false |
| summary | rework / parked wake-up / rebase re-review / stuck triage — the missing transitions from the FSM audit |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A8 |
| blocked_by | #43, #44 |
| parallel_group | G2 (parallel) |
| paths | skills/finish-work/SKILL.md, skills/finish-work/references/flow.md, skills/start-work/SKILL.md |
| solo_merge | yes |
| **primary_ticket** | tkt-49 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-49-reentry-edges |
| worktree | sibling …/lattice.worktrees/tkt-49-reentry-edges/ |
| prs | https://github.com/percena/lattice/pull/57 |

## Acceptance (this slice)

- [x] **A8** (a) a PR returned with findings moves its binder to `status: rework` with findings as the new brief and re-enters the queue; start-work resume honors `rework`; (b) ratifying a pending decision atomically writes the decision into the binder and flips `parked → queued`; (c) finish-work re-runs its embedded mini-review when a base update materially changes the diff (conflict or non-trivial rebase) and carries clean-rebase verdicts unchanged; (d) stuck triage exits documented in start-work resume: unblock→re-queue / re-scope→Spec-or-ticket revision / cancel

## Notes

- start-work/SKILL.md is also touched by tkt-43 (G1) — serialized by layer barrier, no same-layer overlap
- Rework brief = findings from review-delivery digest or human PR review — mechanism must work with both
- No new loops without a declared upper bound (ADR-004 §5)

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` §1, §6
- Review: `rev-20260826-141124Z` Finding 7 (missing exits + cross-machine edges)

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-49**
- Related / sub-tickets: (none)
- Covers: **A8**
- Blocked by: **#43, #44**
- Parallel group: **G2 (parallel)**
- Worktree bind: `tkt-49-reentry-edges`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
