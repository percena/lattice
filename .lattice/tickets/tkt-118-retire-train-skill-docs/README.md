# tkt-118-retire-train-skill-docs

> **TL;DR:** Remove all release-train references from batch-work/finish-work/create-tickets; add dev→main version-bump check to finish-work
> **Kind:** refactor · **Status:** open · **Priority:** P1
> **Path:** spc-116 → tkt-118 → (pr-…)

| Field | Value |
| --- | --- |
| kind | refactor |
| priority | P1 |
| labels | enhancement, P1 |
| github | https://github.com/percena/lattice/issues/118 |
| status | closed |
| adopted | false |
| summary | Retire train docs from 3 skills; add finish-work dev→main version-bump check step |
| spec | spc-116 — retire release-train mechanism (path: ../../specs/spc-116-retire-release-train.md) |
| covers | A7, A8 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md, skills/finish-work/references/flow.md, skills/create-tickets/references/policy.md |
| solo_merge | yes |
| **primary_ticket** | tkt-118 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-118-retire-train-skill-docs` |
| worktree | sibling `…/lattice.worktrees/tkt-118-retire-train-skill-docs/` |
| prs | pr-125 — https://github.com/percena/lattice/pull/125 |

## Acceptance (this slice)

- [x] **A7** — batch-work SKILL.md + flow.md, finish-work flow.md, create-tickets policy.md contain zero references to "release-train", "train_cut", "train mode", "--no-train", or "version cut"
- [x] **A8** — finish-work flow.md has a new dev→main pre-merge step: detects bundle-changed-without-bump before merging to main, surfaces to operator (bump is manual, gate is automated)

## Notes

- Parallel with tkt-117 (path-independent: skills/ vs tools/)
- The new finish-work dev→main check step must slot after CI green, before the merge commit
- Keep the superset conflict law and file-explicit conflict law in §3.4 — just drop "train" wording

## References

- GitHub issue: https://github.com/percena/lattice/issues/118
- Spec: `spc-116` (path above)
- ADR: `ADR-005` → `docs/adr/005-version-bump-at-release-boundary.md`

## Lineage

- Parent spec: **spc-116**
- Parent issue (GH sub-issue): **#116**
- Primary ticket: **tkt-118**
- Covers: **A7, A8**
- Blocked by: (none)
- Parallel group: **G1** (parallel with tkt-117)

## Finish

- pr-125 merged: 2026-08-27T06:51:38Z — https://github.com/percena/lattice/pull/125 (base merge)
- issue #118 closed: 2026-08-27T06:52:24Z — https://github.com/percena/lattice/issues/118
