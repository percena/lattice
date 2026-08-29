# tkt-201 — Docs + small-script hygiene batch

> **Status:** queued · kind chore · priority P2 · covers spc-186 A7

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | chore | |
| priority | P2 | |
| labels | chore, docs, P2 | |
| github | https://github.com/percena/lattice/issues/201 | |
| status | queued | |
| adopted | false | |
| summary | Batch the low-risk doc/script hygiene findings from rev-20260829-160834Z: stale comments, portability citation fixes, FSM entry edges, amendment sediment, small script exit-code quirks. | |
| spec | spc-186 | |
| covers | A7 | |
| blocked_by | tkt-188, tkt-193 | shares workflow-fsm.md + finish-work SKILL.md hot files |
| parallel_group | g4 | layer 4 |
| paths | docs/workflow-fsm.md, docs/morning-triage.md, docs/getting-started.md, skills/_lattice-lib/scripts/reconcile-state.sh, skills/create-adr/scripts/append-adr-index-row.sh, skills/finish-work/SKILL.md | |
| solo_merge | true | one PR |
| primary_ticket | tkt-201 | |
| related_tickets | tkt-188, tkt-193 | blockers (shared docs) |
| worktree_bind | (pending start-work) | |
| worktree | (pending start-work) | |
| prs | (none) | |

## Acceptance (this slice)

- [ ] finish-work SKILL.md marker-wording contradiction (C3) resolved (consistent with tkt-188's fix)
- [ ] reconcile-state.sh:588-591 stale comment fixed (matches the code below at :592-604)
- [ ] Portability claims reconciled: skills citing monorepo `docs/` as authoritative SoT either vendor a minimal reference into `_lattice-lib/references/` or soften the citation (C5)
- [ ] workflow-fsm.md gains missing entry edges (rev `spawn_*`, verify-features bug tickets, S-class fast path) and amendment history sedimented into ADR-004's amendment block (not inline)
- [ ] append-adr-index-row.sh idempotent re-run exits 0 (not nonzero) when row already present
- [ ] github-issue-parent-add.sh node-id resolution bug (found mid-batch: passes issue number as global node id) — fix or file separately
- [ ] All docs changes validated by tools/validate-lattice-artifacts.py (0 errors)

## Approach

Drive-by hygiene batch touching only docs + two small scripts. Each item is low-risk and independent. Reconcile the inline amendment sediment in workflow-fsm.md by moving change-history into ADR-004's existing amendment block (the FSM doc keeps current-state only). The append-adr-index-row exit-code and parent-add node-id bugs are real script defects discovered this session — fix in this batch (small, isolated).

## Anticipated decisions

- **Vendor vs soften for portability** — agent-decides: recommend vendoring a minimal FSM/status-vocab reference into _lattice-lib/references/ (keeps the authoritative pointer portable).
- **github-issue-parent-add fix scope** — agent-decides: if the fix is non-trivial, split to its own ticket; if a one-liner node-id resolution, include here.

## Decision journal

- 2026-08-29: created from spc-186 POST_SPLIT (P2-8). Layer 4 behind tkt-188 + tkt-193 (shared workflow-fsm.md + finish-work SKILL.md).

## Pending decisions

(none)

## Notes

- - NOTICED: github-issue-parent-add.sh passes issue number `187` where the GraphQL mutation expects a node global id; `addSubIssue` fails with "Could not resolve to a node with the global id of '187'". Real script bug. Disposition in this ticket's scope.
- Blocked by tkt-188 (finish-work SKILL.md §3.4 marker wording) and tkt-193 (workflow-fsm.md fix-cycles + cap-exit) — shared hot files.

## References

- Spec: spc-186
- Law: ADR-007
- Review: rev-20260829-160834Z (Findings F4, F5, F6; C4, C5)
- GH issue: #195

## Lineage

- Parent spec: spc-186
- Primary ticket: tkt-201
- Related: tkt-188, tkt-193 (blockers)
- Covers: A7
- Blocked by: tkt-188, tkt-193
- Parallel group: g4
