# tkt-119-ci-context-sensitive-base-ref

> **TL;DR:** CI base-ref context-sensitive (dev lenient / main strict); ci-local --release-check flag
> **Kind:** refactor · **Status:** open · **Priority:** P1
> **Path:** spc-116 → tkt-119 → (pr-…)

| Field | Value |
| --- | --- |
| kind | refactor |
| priority | P1 |
| labels | enhancement, P1 |
| github | https://github.com/percena/lattice/issues/119 |
| status | in-progress |
| adopted | false |
| summary | CI + ci-local pass correct base-ref: fork point for dev (lenient), origin/main for main (strict) |
| spec | spc-116 — retire release-train mechanism (path: ../../specs/spc-116-retire-release-train.md) |
| covers | A5, A6 |
| blocked_by | tkt-117 |
| parallel_group | G2 |
| paths | .github/workflows/lint-heavy.yml, tools/ci-local.sh |
| solo_merge | yes |
| **primary_ticket** | tkt-119 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-119-ci-context-sensitive-base-ref` |
| worktree | sibling `…/lattice.worktrees/tkt-119-ci-context-sensitive-base-ref/` |
| prs | (none) · pr-125 — https://github.com/percena/lattice/pull/125 |

## Acceptance (this slice)

- [x] **A5** — lint-heavy.yml green on dev merges (lenient, no false red) AND on main-target PRs (strict, catches missing bump)
- [x] **A6** — ci-local.sh default is lenient (dev-mode: non-decrease only); `--release-check` flag triggers strict release-boundary validation against `origin/main`

## Notes

- Depends on tkt-117: CI semantics follow the validator's final release-boundary logic
- Highest-risk change: GitHub Actions expression logic for base-ref context-sensitivity; a bug could suppress real reds on main or reintroduce false reds on dev
- Mitigation: test the expression logic locally before pushing

## References

- GitHub issue: https://github.com/percena/lattice/issues/119
- Spec: `spc-116` (path above)
- ADR: `ADR-005` → `docs/adr/005-version-bump-at-release-boundary.md`
- Depends on: tkt-117

## Lineage

- Parent spec: **spc-116**
- Parent issue (GH sub-issue): **#116**
- Primary ticket: **tkt-119**
- Covers: **A5, A6**
- Blocked by: **tkt-117**
- Parallel group: **G2**

## Finish

- pr-125 merged: 2026-08-27T06:51:38Z — https://github.com/percena/lattice/pull/125 (base merge)
- issue #119 closed: 2026-08-27T06:52:28Z — https://github.com/percena/lattice/issues/119
