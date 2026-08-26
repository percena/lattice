# tkt-45-workflow-docs

> **TL;DR:** docs/workflow-fsm.md (three coupled machines, transition owners, bounded-loop invariant) + docs/day-phase.md (business req → proposal rev → spec → adr → tickets recipe)
> **Kind:** docs · **Status:** open · **Priority:** P2
> **Path:** spc-42 → tkt-45 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | documentation, P2 |
| github | https://github.com/percena/lattice/issues/45 |
| status | open |
| adopted | false |
| summary | workflow FSM reference + day-phase recipe docs; README docs-table rows |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A9 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | docs/workflow-fsm.md (new), docs/day-phase.md (new), README.md |
| solo_merge | yes |
| **primary_ticket** | tkt-45 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-45-workflow-docs |
| worktree | sibling …/lattice.worktrees/tkt-45-workflow-docs/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A9** `docs/workflow-fsm.md` records the three coupled machines (planning / execution / knowledge), the transition table with owners, the human-owned transition white-list (macro sign-off, ratify, deep-review verdict, Spec revision, cancel, merge), and the bounded-loop invariant; `docs/day-phase.md` records the recipe — business requirement → solution-proposal rev (2–3 options + recommendation + rejected-alternatives attestation) → spec → adr → tickets; README docs table updated

## Notes

- Source material: `rev-20260826-141124Z` Findings 1, 2, 7 — distill, do not duplicate the whole rev
- States/enum wording must match tkt-44's final template (docs can land first; wording is already fixed by spc-42 A4)

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` §1
- Review: `rev-20260826-141124Z`

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-45**
- Related / sub-tickets: (none)
- Covers: **A9**
- Blocked by: (none)
- Parallel group: **G1 (parallel)**
- Worktree bind: `tkt-45-workflow-docs`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
