# tkt-108-audit-recipe

> **TL;DR:** The operator-praised audit method becomes skill law — a six-element audit recipe for create-review (fan-out, verify-then-report, enforcement-coverage, claim reconciliation, history archaeology, mechanism pairing) plus one claim-reconciliation line in review-code's docs-sync axis
> **Kind:** docs · **Priority:** P2
> **Path:** (ticket-only) → tkt-108 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | documentation, P2 |
| github | https://github.com/percena/lattice/issues/108 |
| status | closed |
| adopted | false |
| summary | create-review references/audit-recipe.md + kind:audit + verify-then-report DEFAULT; review-code docs-sync claim-reconciliation line |
| spec | none — operator request 2026-08-27; design in rev-20260827-042618Z §review-skill audit upgrades |
| covers | operator request: encode the audit method |
| blocked_by | (none — rides the spc-104 train for the version cut only) |
| parallel_group | G1 (wave 2; path-disjoint with tkt-105/106/107) |
| paths | skills/create-review/SKILL.md, skills/create-review/references/audit-recipe.md (new), skills/review-code/references/docs-sync.md |
| solo_merge | yes |
| **primary_ticket** | tkt-108 (this issue) |
| **related_tickets** | (method demonstrated in) the rev-20260827-033352Z audit → tkt-90…96 |
| **worktree_bind** | tkt-108-audit-recipe |
| worktree | sibling …/lattice.worktrees/tkt-108-audit-recipe/ |
| prs | pr-112 — https://github.com/percena/lattice/pull/112 |

## Acceptance (this slice)

- [x] **A1** `create-review/references/audit-recipe.md`: the six elements — orthogonal fan-out (parallel read-only sweeps over disjoint concerns, overlap tolerated, gaps not); verify-then-report; enforcement-coverage axis ("which check enforces this law?" — unenforced law is itself a finding); claim–implementation reconciliation (execute the doc's promise against the tool); history archaeology (CI red-run mining + recurring-deferral mining; every finding marked already-addressed-or-not); root-cause clustering with mechanism pairing (every spawned ticket pairs repair with prevention) — with the rev-20260827-033352Z audit as the worked example
- [x] **A2** create-review SKILL.md: Load-on-demand row for the recipe; `kind: audit` documented; verify-then-report as a DEFAULT core rule (claims enter Findings only after re-verification with file:line evidence; dropped-claim count recorded)
- [x] **A3** review-code `references/docs-sync.md`: one claim-reconciliation line
- [x] **A4** validate-skills + ci-local green; carries the shared 0.3.0 cut byte-identically

## Approach

Reference doc in the house table style (severity-tagged rules, Common Rationalizations, Verification). Keep create-review's core-rule numbering intact (append, don't renumber). The recipe explicitly notes it composes with the existing Problem Audit DEFAULT (validity/sufficiency before solutions) rather than replacing it.

## Anticipated decisions

- Where fan-out guidance lives — pre-resolved: in the recipe (create-review), citing orchestration-patterns.md for delegation law rather than duplicating it

## Decision journal

- Core-rule numbering: appended as rule **9** (existing 1/1b…8 untouched); verify-then-report scoped as DEFAULT for findings-class reviews (the INVARIANT form lives in the recipe where kind: audit applies) — chain source 1 (binder Approach: append, don't renumber); reversible.
- docs-sync placement: claim-reconciliation lands as step 5 of the existing "Stale detection" numbered list (the per-doc comparison loop) rather than a new section — one line in existing structure per A3 — chain source 1; reversible.
- Recipe severity split: element 2 (verify-then-report) tagged INVARIANT as "the core law" per design rev; the other five DEFAULT — matches constraint-language.md (outcome-bound vs happy-path) — chain source 1 (rev-20260827-042618Z §audit upgrades); reversible.
- `kind: audit` documented inline in the §2 Write field table (the only place kinds are enumerated in SKILL.md), pointing at the recipe — minimal wiring — chain source 1; reversible.

## Pending decisions

## Attempts

## Notes

- Origin: operator 2026-08-27 — "这两轮 review 的逻辑很不错…结合项目中的 review skill 看有没有可以进一步优化的地方"

## References

- rev-20260827-042618Z · rev-20260827-033352Z (worked example) · create-review SKILL.md (Problem Audit DEFAULT)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-108** · Parallel group: **G1 (wave 2)** · Worktree bind: `tkt-108-audit-recipe`

## Finish

- pr-112 merged: 2026-08-27T05:40:35Z — https://github.com/percena/lattice/pull/112 (base merge)
- issue #108 closed: 2026-08-27T05:40:40Z — https://github.com/percena/lattice/issues/108
