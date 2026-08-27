# tkt-94-registration-surfaces

> **TL;DR:** Every shipped skill appears on every registration surface (manifests, plugin README, llms.txt, lib inventory, routing catalog) — and validate-skills makes the whole drift class a CI failure from now on
> **Kind:** chore · **Priority:** P2
> **Path:** (ticket-only) → tkt-94 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/94 |
| status | queued |
| adopted | false |
| summary | 13-skill parity on all surfaces + validate-skills keyword/README assertions + routing-catalog cross-check + CONTRIBUTING checklist |
| spec | none — audit rev-20260827-033352Z F6 |
| covers | audit F6 |
| blocked_by | (none) |
| parallel_group | G1 (wave 1) |
| paths | .claude-plugin/marketplace.json, plugins/lattice/.claude-plugin/plugin.json, plugins/lattice/README.md, llms.txt, skills/_lattice-lib/SKILL.md, tools/validate-skills.sh, tools/run-routing-evals.py, evals/routing/**, CONTRIBUTING.md |
| solo_merge | yes |
| **primary_ticket** | tkt-94 (this issue) |
| **related_tickets** | tkt-61 (registration-integrity precedent this extends), tkt-75 (README skill-table backfill precedent) |
| **worktree_bind** | tkt-94-registration-surfaces |
| worktree | sibling …/lattice.worktrees/tkt-94-registration-surfaces/ |
| prs | (none yet) |

## Acceptance (this slice)

- [ ] **A1** both manifests: descriptions + keywords name all 13 user-facing skills; files agree with each other
- [ ] **A2** `plugins/lattice/README.md`: component table + skills list + install example cover all 14 units; hooks heading current
- [ ] **A3** `llms.txt` regenerated (13 skills, live anchors, full docs list)
- [ ] **A4** `_lattice-lib/SKILL.md`: user-facing count corrected; script table lists all shipped runtime scripts
- [ ] **A5** `validate-skills.sh`: USER_FACING ∈ both manifests' keywords + plugins/lattice/README.md (error); routing catalog asserted against USER_FACING (with cases added or documented exclusions for batch-work/run-e2e/review-delivery)
- [ ] **A6** CONTRIBUTING new-skill checklist names every surface above; full `ci-local` green

## Approach

Mechanical parity edits first (A1–A4), then the enforcement (A5): extend the existing registration-integrity loop in validate-skills.sh (it already enumerates USER_FACING) with grep assertions per surface; add a catalog-parity check to run-routing-evals.py (compare CATALOG against an env/args-passed list or read the same source; simplest: a bats test in tools/tests asserting set equality between the two lists' sources). Routing cases for the 3 uncovered skills: add minimal 2-prompt cases each if cheap; else EXCLUDED list with reason comments, asserted so removal of the reason fails. CONTRIBUTING checklist: one surface per line so future greps hit it.

## Anticipated decisions

- Routing coverage vs documented exclusion for the 3 skills — disposition: agent-decides (prefer real minimal cases; journal)
- llms.txt structure — pre-resolved: keep current format, regenerate content only (generate-wiki owns richer generation)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Root cause is the CONTRIBUTING checklist gap: every stale surface is exactly a surface the checklist omits; getting-started (on the list) stayed current

## References

- rev-20260827-033352Z F6 · tkt-61 (#67) · CONTRIBUTING.md new-skill checklist

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-94** · Parallel group: **G1 (wave 1)** · Worktree bind: `tkt-94-registration-surfaces`

## Finish
