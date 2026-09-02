# tkt-372-review-lineage-skill

> **TL;DR:** SKILL.md + method/taxonomy/template: the three-layer mining protocol, verify-then-report, insight ranking, rev output with a Proposed-tickets table.
> **Kind:** feat · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/372 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T07:21:07Z |
| updated | 2026-09-02T07:21:07Z |
| adopted | false |
| summary | SKILL.md + method/taxonomy/template: the three-layer mining protocol, verify-then-report, insight ranking, rev output with a Proposed-tickets table. |
| spec | spc-369 — review-lineage (path: ../../specs/spc-369-review-lineage.md) |
| covers | A3 |
| blocked_by | #370, #371 |
| merge_blocked_by | #370, #371 |
| parallel_group | (serial) |
| paths | skills/review-lineage/SKILL.md, skills/review-lineage/references/method.md, skills/review-lineage/references/insight-taxonomy.md, skills/review-lineage/references/templates/lineage-audit.md |
| solo_merge | yes |
| **primary_ticket** | tkt-372 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-372-review-lineage-skill |
| worktree | sibling `…/lattice.worktrees/tkt-372-review-lineage-skill/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A3** — see GitHub issue #372 and Spec spc-369 A3.

## Approach

1. SKILL.md modelled on review-delivery's shape (frontmatter with `domain: quality-side-path`, Load-on-demand table, When to use/NOT, Invariants, Inputs, Process 0–5, Outputs, anatomy footers); Step 0 runs `lineage-metrics.sh --md`, `claim-probes.sh --md`, `validate-lattice-artifacts.py`, optional `reconcile-state.sh`.
2. method.md: L1/L2/L3 commands and the ranking rubric (impact × decidability), fan-out guidance citing orchestration-patterns.md, verify-then-report with dropped-claim accounting (audit-recipe §2).
3. insight-taxonomy.md: modelled-but-unwalked, claim-without-enforcement, done-without-evidence, silent-bypass, recurrence, invisible-queue, prose-vs-script ratio, artifact-truth (checked box ≠ proven) — each with detection hint + example from rev-20260902-015425Z.
4. templates/lineage-audit.md: rev frontmatter (kind audit), Metrics delta, Probe failures, Findings (≤7), Insights, Proposed tickets (title | kind | priority | covers | paths | blocked_by | why), Outcome, Method (sweeps, dropped claims), References.
5. Dry-run the skill on this repo; the produced rev is NOT committed by this ticket (it is evidence in the PR body), or committed under .lattice/reviews/ if the operator wants the first baseline.

## Anticipated decisions

- Whether the dry-run rev is committed — must-ask (default: commit it as the first baseline; it is a real audit).

## Decision journal

## Pending decisions

(none)

## Attempts

## Notes

## References

- Spec: `spc-369` → `.lattice/specs/spc-369-review-lineage.md`
- Review: `rev-20260902-015425Z` (method origin)

## Lineage

- Parent spec: **spc-369**
- Parent issue (GH sub-issue of Spec primary): **#369**
- Primary ticket: **tkt-372**
- Covers: **A3**
- Blocked by: #370, #371
- Parallel group: (serial)
- Worktree bind: tkt-372-review-lineage-skill

## Finish

- (none yet)
