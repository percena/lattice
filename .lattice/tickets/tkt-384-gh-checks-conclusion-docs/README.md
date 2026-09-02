# tkt-384-gh-checks-conclusion-docs

> **TL;DR:** Drop `conclusion` from the documented `gh pr checks --json` field list in 3 doc lines; the `retired-paths-absent` probe keeps them fixed.
> **Kind:** docs · **Priority:** P3
> **Path:** rev-20260902-080545Z F4 → tkt-384 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | documentation, P3 |
| github | https://github.com/percena/lattice/issues/384 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:20:35Z |
| updated | 2026-09-02T12:01:29Z |
| adopted | false |
| summary | drop conclusion from documented gh pr checks --json field list (3 doc lines) |
| spec | (none — spawned from rev-20260902-080545Z) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G2 |
| paths | skills/finish-work/references/flow.md, skills/review-code/SKILL.md, skills/review-code/references/ci-check.md |
| solo_merge | yes |
| primary_ticket | tkt-384 |
| related_tickets | (none) |
| worktree_bind | tkt-384-gh-checks-conclusion-docs |
| worktree | sibling `…/<repo>.worktrees/tkt-384-gh-checks-conclusion-docs/` |
| prs | pr-396 — https://github.com/percena/lattice/pull/396 |

## Acceptance (this slice)

- [x] **A1** No doc line in `skills/` or `docs/` references `name,state,conclusion,link` (grep clean — excluding `retired-paths.txt` which documents the retired field, and `ci-gate-check.bats` which tests for its absence).
- [x] **A2** `retired-paths-absent` probe passes (no `med` fail row for this class).

## Approach

Three one-line fixes: `skills/finish-work/references/flow.md:45` — drop `conclusion` from the `--json` field list in the prose describing the CI gate. `skills/review-code/SKILL.md:122` — same. `skills/review-code/references/ci-check.md:14` — same bare command. Replace `name,state,conclusion,link` with `name,state,link` (or `name,state,bucket,link` if the doc wants the gh 2.6x fields). The script already derives the legacy pair (`ci-gate-check.sh:138-146`); the docs just need to match.

**Touch-set:** `skills/finish-work/references/flow.md:45`, `skills/review-code/SKILL.md:122`, `skills/review-code/references/ci-check.md:14`.

## Anticipated decisions

- replacement field list — pre-resolved (tkt-349 + ci-gate-check.sh:138-146): the script uses `name,state,link` (derives `conclusion` internally); docs should match.
- retired-paths.txt — pre-resolved: leave as-is; it documents the retired field (correct), not a doc to fix.
- ci-gate-check.bats reference — pre-resolved: leave as-is; the bats test asserts the field is absent from the script (correct).

## Decision journal

## Pending decisions

## Attempts

## Notes

- Origin: `rev-20260902-080545Z` F4 (lineage-audit baseline, spc-369 dry run).
- The script was already fixed by tkt-349; only the doc lines remain.

## References

- GitHub issue: #384
- Review: `rev-20260902-080545Z` Finding F4
- Prior fix: tkt-349 (script-side `ci-gate-check.sh` fix)
- Probe: `retired-paths-absent` in `skills/review-lineage/references/probes.md`

## Lineage

- Parent spec: (none — spawned from review)
- Parent issue: none (ticket-only)
- Primary ticket: tkt-384
- Related / sub-tickets: (none)
- Covers: (none)
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G2
- Worktree bind: tkt-384-gh-checks-conclusion-docs
- Child PRs: (none yet)

## Assets

## Finish


- pr-396 merged: 2026-09-02T12:01:03Z — https://github.com/percena/lattice/pull/396 (base merge)
- issue #384 closed: 2026-09-02T12:01:22Z — https://github.com/percena/lattice/issues/384
