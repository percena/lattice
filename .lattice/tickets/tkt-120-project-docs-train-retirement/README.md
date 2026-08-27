# tkt-120-project-docs-train-retirement

> **TL;DR:** Update CONTRIBUTING + tools/README + CHANGELOG to reflect release-boundary enforcement
> **Kind:** docs · **Status:** open · **Priority:** P1
> **Path:** spc-116 → tkt-120 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P1 |
| labels | documentation, P1 |
| github | https://github.com/percena/lattice/issues/120 |
| status | in-progress |
| adopted | false |
| summary | Project docs reflect release-boundary version enforcement + CHANGELOG records train retirement |
| spec | spc-116 — retire release-train mechanism (path: ../../specs/spc-116-retire-release-train.md) |
| covers | A9, A10 |
| blocked_by | tkt-117, tkt-118 |
| parallel_group | G2 |
| paths | CONTRIBUTING.md, tools/README.md, CHANGELOG.md, plugins/lattice/CHANGELOG.md |
| solo_merge | yes |
| **primary_ticket** | tkt-120 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-120-project-docs-train-retirement` |
| worktree | sibling `…/lattice.worktrees/tkt-120-project-docs-train-retirement/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A9** — CONTRIBUTING step 14 and base-ref examples reflect release-boundary enforcement; tools/README validator description updated
- [ ] **A10** — CHANGELOG (root + plugin) has a train-retirement entry under Unreleased

## Notes

- Depends on tkt-117 + tkt-118: docs must reflect the final behavior of both code and skill docs
- CHANGELOG entry should cite ADR-005 + spc-116

## References

- GitHub issue: https://github.com/percena/lattice/issues/120
- Spec: `spc-116` (path above)
- ADR: `ADR-005` → `docs/adr/005-version-bump-at-release-boundary.md`
- Depends on: tkt-117, tkt-118

## Lineage

- Parent spec: **spc-116**
- Parent issue (GH sub-issue): **#116**
- Primary ticket: **tkt-120**
- Covers: **A9, A10**
- Blocked by: **tkt-117, tkt-118**
- Parallel group: **G2**
