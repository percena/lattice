# tkt-161-docs-drift-sweep

> **TL;DR:** Sweep the FSM / train-retirement documentation drift: ADR-005 index status, broken Mermaid note, wrong evals path, missing ratify.sh row, plugin README co-install, morning-triage indexing.
> **Kind:** docs · **Priority:** P2
> **Path:** repo-review 2026-08-28 → tkt-161 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs, P2 |
| github | https://github.com/percena/lattice/issues/161 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | Six drift fixes across docs/evals/plugins/README surfaces + morning-triage indexing |
| spec | (none — ticket-only) |
| covers | A1-A7 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | docs/adr/README.md; docs/workflow-fsm.md; docs/getting-started.md; evals/README.md; plugins/lattice/README.md; skills/_lattice-lib/SKILL.md; README.md; README.zh-CN.md; llms.txt |
| solo_merge | yes |
| **primary_ticket** | tkt-161 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-161-docs-drift-sweep` |
| worktree | sibling `…/lattice.worktrees/tkt-161-docs-drift-sweep/` |
| prs | pr-171 — https://github.com/percena/lattice/pull/171 |

## Acceptance (this slice)

- [x] **A1** ADR index ADR-005 row = Accepted (matches body).
- [x] **A2** workflow-fsm.md Mermaid block renders (valid `note … end note` or prose outside the diagram).
- [x] **A3** evals/README.md bats path points at the real suite (`tools/tests/behavioral-evals.bats`).
- [x] **A4** `_lattice-lib/SKILL.md` scripts table includes `ratify.sh`.
- [x] **A5** plugins README co-install note includes `verify-features`; unit count wording consistent (14 user-facing + lib).
- [x] **A6** morning-triage indexed in README.md, README.zh-CN.md, llms.txt, getting-started.md.

## Deferred verification (not acceptance of this PR)

- After tkt-150 and tkt-151 land (their worktrees own the files): verify `docs/morning-triage.md` Step 4 staleness (fuse-halt "stay queued" / "Known gap (FSM-2)") and batch-work "six contract items" (×2) are fixed by those tickets; if not, file a follow-up.

## Notes

- **Collision avoidance:** do NOT edit `docs/morning-triage.md` (in-flight tkt-150 scope) or `skills/batch-work/SKILL.md` (in-flight tkt-151 scope). A7 tracks the residual verification instead.
- Do not run in the same parallel wave as tkt-150/tkt-151.

## References

- tkt-132/135/137/138 (pr-142) — FSM honesty fixes that introduced the drift
- ADR-005; tkt-134 (morning-triage); tkt-136 (ratify.sh)

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-161**
- Covers: A1-A7
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-161-docs-drift-sweep`

## Finish


- pr-171 merged: 2026-08-28T11:26:34Z — https://github.com/percena/lattice/pull/171 (base merge)
- issue #161 closed: 2026-08-28T11:26:40Z — https://github.com/percena/lattice/issues/161
