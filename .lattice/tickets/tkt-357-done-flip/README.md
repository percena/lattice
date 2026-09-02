# tkt-357-done-flip

> **TL;DR:** Record spc-337 dogfood/soak conclusion, flip Spec status locked → done, close #337.
> **Kind:** chore · **Priority:** P3

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore,P3 |
| github | https://github.com/percena/lattice/issues/357 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T05:19:22Z |
| updated | 2026-09-02T05:22:24Z |
| adopted | false |
| summary | Record spc-337 dogfood/soak conclusion, flip Spec status locked → done, close #337. |
| spec | spc-337 — FSM conformance closure (path: ../../specs/spc-337-fsm-conformance-closure.md) |
| covers | spc-337 done-gate (ADR-012 §6) |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | .lattice/specs/spc-337-fsm-conformance-closure.md |
| solo_merge | yes |
| **primary_ticket** | tkt-357 (this issue) |
| worktree_bind | tkt-357-done-flip |
| prs | pr-358 — https://github.com/percena/lattice/pull/358 |

## Acceptance (this slice)

- [x] spec front-matter `status: done`.
- [x] status-history entry documents: CI green (artifacts, lattice-scripts, plugin-hooks, lint all success post pr-355), metrics (219 legacy warnings + 0 errors; ledger coverage 42/145; direct jumps 10), 4 follow-ups fixed (#349, #350, #352, #353), #356 filed.
- [x] `validate-lattice-artifacts.py` passes on the updated spec.
- [x] #337 closed on GitHub.

## Approach

1. Edit `.lattice/specs/spc-337-fsm-conformance-closure.md` front-matter: `status: locked` → `status: done`; bump `updated` to 2026-09-02.
2. Update `tickets:` list to include follow-ups tkt-349, tkt-350, tkt-352, tkt-353, tkt-356, tkt-357.
3. Append status-history bullet documenting the dogfood/soak results.
4. `gh issue close 337` after PR merge.

Touch-set: `.lattice/specs/spc-337-fsm-conformance-closure.md`.

## Anticipated decisions

- Done-gate satisfaction — pre-resolved (ADR-012 §6: all child binders closed ✓, prs list = child PR union ✓, one dogfood cycle passed ✓ via 4 follow-up bugs surfaced + fixed).

## Decision journal

## Notes

- ADR-012 §6 done-gate conditions verified during dogfood cycle on 2026-09-02:
  - (a) All child binders closed — #338..342 all CLOSED.
  - (b) `prs` list = child PR union — pr-344..348 (+ follow-up pr-354, pr-355).
  - (c) At least one dogfood cycle has passed since the last child merge — satisfied (4 follow-up bugs surfaced and fixed).

## Lineage

- Parent spec: **spc-337**
- Parent issue (GH sub-issue of Spec primary #337): **#337**
- Primary ticket: **tkt-357**
- Refs: #356 (macOS A4 follow-up, filed this pass), ADR-012 §6
- Covers: **spc-337 done-gate**
- Worktree bind: tkt-357-done-flip
- Child PRs: (none yet)

## Assets

## Finish

- (none yet)
