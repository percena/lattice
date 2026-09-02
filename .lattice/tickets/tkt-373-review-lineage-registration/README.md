# tkt-373-review-lineage-registration

> **TL;DR:** Registration surfaces, routing eval, weekly cadence recipe, and the M3 edge for review-lineage.
> **Kind:** docs · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs,P2 |
| github | https://github.com/percena/lattice/issues/373 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T07:21:07Z |
| updated | 2026-09-02T08:34:30Z |
| adopted | false |
| summary | Registration surfaces, routing eval, weekly cadence recipe, and the M3 edge for review-lineage. |
| spec | spc-369 — review-lineage (path: ../../specs/spc-369-review-lineage.md) |
| covers | A4 |
| blocked_by | #372 |
| merge_blocked_by | #372 |
| parallel_group | (serial) |
| paths | README.md, README.zh-CN.md, llms.txt, plugins/lattice/README.md, plugins/lattice/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, plugins/lattice/skills/review-lineage, docs/getting-started.md, docs/morning-triage.md, docs/workflow-fsm.md, evals/routing/review-lineage.json |
| solo_merge | yes |
| **primary_ticket** | tkt-373 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-373-review-lineage-registration |
| worktree | sibling `…/lattice.worktrees/tkt-373-review-lineage-registration/` |
| prs | (none) |

## Acceptance (this slice)

- [x] **A4** — review-lineage on every registration surface (README/zh, llms.txt, plugin README + install line + co-install, plugin.json + marketplace.json description/keywords, getting-started side-paths + row), USER_FACING + QUALITY_SIDE_PATHS in validate-skills (EXEMPT bridge removed), routing CATALOG + `evals/routing/review-lineage.json` (4 positive EN+ZH, 5 negatives; rank1 4/4), morning-triage Step 7 (weekly + after each Spec closes), workflow-fsm M3 block + table row.

## Approach

1. Mirror every `review-delivery` occurrence on the registration surfaces (grep list in the issue) with a `review-lineage` row; add the `plugins/lattice/skills/review-lineage` symlink (relative, like siblings).
2. `evals/routing/review-lineage.json`: aliases (挖掘遗漏/蒸馏 tickets/lineage audit/periodic audit), ≥3 positive (EN+ZH), negatives that must route to review-delivery, create-review, verify-features; run `python3 tools/run-routing-evals.py --min-rank1 80`.
3. docs: morning-triage weekly step (after Step 6), getting-started optional-skills row, workflow-fsm M3 table row + one sentence in §1 M3.
4. `tools/validate-skills.sh` + `ci-local.sh --fast` green.

## Anticipated decisions

- Weekly vs per-Spec cadence wording — pre-resolved(spc-369 In scope): both stated (weekly, and after each Spec closes).

## Decision journal

- 2026-09-02 validate-skills.bats fixture list (`user_facing` at :41) must mirror USER_FACING — added review-lineage there (the green-fixture and plugin-bundle tests enumerate the list by hand); NOTICED that the list is duplicated between the lint and its test (source: agent-judgment, ticket-local).
- 2026-09-02 cadence wording: weekly AND after each Spec closes, per spc-369 In scope (pre-resolved).

## Pending decisions

(none)

## Attempts

## Notes

- NOTICED: tools/tests/validate-skills.bats:41 — USER_FACING is hand-duplicated in the bats fixture list; a new user-facing skill silently breaks the suite until both are edited (out-of-paths for the lint itself; tkt-373 edited the line, 2026-09-02)

## References

- Spec: `spc-369` → `.lattice/specs/spc-369-review-lineage.md`
- Review: `rev-20260902-015425Z` (method origin)

## Lineage

- Parent spec: **spc-369**
- Parent issue (GH sub-issue of Spec primary): **#369**
- Primary ticket: **tkt-373**
- Covers: **A4**
- Blocked by: #372
- Parallel group: (serial)
- Worktree bind: tkt-373-review-lineage-registration

## Finish

- (none yet)
