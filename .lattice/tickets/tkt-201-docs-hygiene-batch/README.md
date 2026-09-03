# tkt-201 — Docs + small-script hygiene batch

> **Status:** closed · kind chore · priority P2 · covers spc-186 A7

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | chore | |
| created | 2026-08-29T17:00:00Z | |
| updated | 2026-08-29T13:46:34Z | |
| priority | P2 | |
| labels | chore, docs, P2 | |
| github | https://github.com/percena/lattice/issues/201 | |
| status | closed | |
| adopted | false | |
| summary | Batch the low-risk doc/script hygiene findings from rev-20260829-160834Z: stale comments, portability citation fixes, FSM entry edges, amendment sediment, small script exit-code quirks. | |
| spec | spc-186 | |
| covers | A7 | |
| blocked_by | tkt-188, tkt-193 | shares workflow-fsm.md + finish-work SKILL.md hot files |
| parallel_group | g4 | layer 4 |
| paths | docs/workflow-fsm.md, skills/_lattice-lib/scripts/reconcile-state.sh, skills/_lattice-lib/scripts/github-issue-parent-add.sh, skills/create-adr/scripts/append-adr-index-row.sh, skills/finish-work/SKILL.md, skills/_lattice-lib/references/workflow-fsm-reference.md, skills/start-work/SKILL.md, skills/batch-work/references/flow.md, skills/finish-work/references/flow.md, skills/_lattice-lib/scripts/check-installed-skill-drift.sh, skills/create-tickets/scripts/sync-github-labels.sh | |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | tkt-188, tkt-193 | blockers (shared docs) |
| worktree_bind | `tkt-201-docs-hygiene-batch` | |
| worktree | sibling `…/lattice.worktrees/tkt-201-docs-hygiene-batch/` | |
| prs | pr-210 — https://github.com/percena/lattice/pull/210 | |

## Acceptance (this slice)

- [x] finish-work SKILL.md marker-wording contradiction (C3) resolved — verified consistent across all three locations (§3.4, §8, §11.2); tkt-188's fix holds, no residual contradiction
- [x] reconcile-state.sh:588-591 stale comment fixed — comment now states `has_finish_ledger`/`finish_ledger_merged` ARE used in drift detection (matching the code at :603-615)
- [x] Portability claims reconciled (C5) — vendored `_lattice-lib/references/workflow-fsm-reference.md`; softened remaining monorepo `docs/` citations with "when present" / "monorepo when present" qualifiers
- [x] workflow-fsm.md gains missing entry edges (rev `spawn_*`, verify-features bug tickets, S-class fast path) in M1 diagram + transition table; amendment sediment removed from §5, replaced with pointer to ADR-004 (amendments already live there)
- [x] append-adr-index-row.sh idempotent re-run exits 0 — verified already correct (existing test "idempotent: second run for same num is a no-op" checks `[ "$status" -eq 0 ]`)
- [x] github-issue-parent-add.sh node-id bug — fixed: added defensive guard that rejects purely-numeric extracted ids (database id, not GraphQL node id), skips GraphQL, falls through to REST; added test "numeric id field skips GraphQL, falls through to REST"
- [x] All docs changes validated by tools/validate-lattice-artifacts.py (0 errors)
- [x] Schema drift: `primary_ticket` standardized to `true` across all 8 spc-186 child binders; `parallel_group` labels aligned with executed DAG layers (tkt-194 g3→g2, tkt-192 g4→g3, tkt-189 missing→g1)

## Approach

Drive-by hygiene batch touching only docs + two small scripts. Each item is low-risk and independent. Reconcile the inline amendment sediment in workflow-fsm.md by moving change-history into ADR-004's existing amendment block (the FSM doc keeps current-state only). The append-adr-index-row exit-code and parent-add node-id bugs are real script defects discovered this session — fix in this batch (small, isolated).

## Anticipated decisions

- **Vendor vs soften for portability** — RESOLVED: chose vendoring (see Decision journal).
- **github-issue-parent-add fix scope** — RESOLVED: trivial one-liner guard, included in this ticket (see Decision journal).

## Decision journal

- 2026-08-29: created from spc-186 POST_SPLIT (P2-8). Layer 4 behind tkt-188 + tkt-193 (shared workflow-fsm.md + finish-work SKILL.md).
- 2026-08-29: **Vendor vs soften for portability (C5)** — chose vendoring. Created `skills/_lattice-lib/references/workflow-fsm-reference.md` as a portable FSM/status-vocab excerpt. Skills that previously cited monorepo `docs/workflow-fsm.md` as the sole SoT now cite the portable reference first, with the monorepo doc as secondary. Rationale: keeps the authoritative pointer portable in a vendored install (no monorepo `docs/` required) while preserving the full monorepo doc as the comprehensive source when present.
- 2026-08-29: **github-issue-parent-add.sh node-id bug** — fixed in this ticket (trivial). Added a defensive guard: if the `id` field extracted from `gh issue view --json id,number` is purely numeric (a database id, not a GraphQL node id like `I_kwD...`), skip the GraphQL addSubIssue path and fall through to REST. The bug manifested when `gh issue view` returned a numeric `id` field; passing it to the GraphQL mutation caused "Could not resolve to a node with the global id of '<number>'". Source: binder NOTICED line + code analysis; resolution: agent-judgment (one-liner guard + test).
- 2026-08-29: **append-adr-index-row.sh exit code** — verified already correct. The existing code exits 0 on idempotent re-run when the row already exists (lines 133-137). Existing test "idempotent: second run for same num is a no-op" confirms `[ "$status" -eq 0 ]`. No fix needed.
- 2026-08-29: **Schema drift (primary_ticket + parallel_group)** — standardized `primary_ticket` to `true` across all 8 spc-186 child binders (per tkt-188/189 convention). Aligned `parallel_group` labels with the executed DAG: tkt-194 g3→g2 (blocked_by tkt-188, layer 1 → layer 2), tkt-192 g4→g3 (blocked_by tkt-191, layer 2 → layer 3), tkt-189 missing→g1 (no blockers, layer 1). Source: dependency DAG + actual PR merge order (PR #197→#209).
- 2026-08-29T13:41:41Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #210) [WARN — signal logged, not silently lost]

## Pending decisions

(none)

## Notes

- NOTICED: github-issue-parent-add.sh passes issue number `187` where the GraphQL mutation expects a node global id; `addSubIssue` fails with "Could not resolve to a node with the global id of '187'". **Resolved in this ticket** — added defensive guard rejecting purely-numeric extracted ids; GraphQL path skips to REST when the `id` field is a database id, not a node id.
- Blocked by tkt-188 (finish-work SKILL.md §3.4 marker wording) and tkt-193 (workflow-fsm.md fix-cycles + cap-exit) — shared hot files.

## References

- Spec: spc-186
- Law: ADR-007
- Review: rev-20260829-160834Z (Findings F4, F5, F6; C4, C5)
- GH issue: #195

## Lineage

- Parent spec: spc-186
- Primary ticket: true
- Related: tkt-188, tkt-193 (blockers)
- Covers: A7
- Blocked by: tkt-188, tkt-193
- Parallel group: g4

## Finish

- pr-210 merged: 2026-08-29T13:46:20Z — https://github.com/percena/lattice/pull/210 (base merge)
- issue #201 closed: 2026-08-29T13:46:30Z — https://github.com/percena/lattice/issues/201
