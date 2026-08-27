# tkt-117-retire-train-validator-core

> **TL;DR:** Delete train_cut_shared + --no-train + linear-push guard; rework strict law to fire only at release-boundary base-ref
> **Kind:** refactor · **Priority:** P1
> **Path:** spc-116 → tkt-117 → (pr-…)

| Field | Value |
| --- | --- |
| kind | refactor |
| priority | P1 |
| labels | enhancement, P1 |
| github | https://github.com/percena/lattice/issues/117 |
| status | closed |
| adopted | false |
| summary | Delete train mechanism from validator; enforce version-bump only at dev→main release boundary |
| spec | spc-116 — retire release-train mechanism (path: ../../specs/spc-116-retire-release-train.md) |
| covers | A1, A2, A3, A4 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | tools/validate-plugin-versions.py, tools/tests/plugin-versions.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-117 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-117-retire-train-validator-core` |
| worktree | sibling `…/lattice.worktrees/tkt-117-retire-train-validator-core/` |
| prs | pr-125 — https://github.com/percena/lattice/pull/125 |

## Acceptance (this slice)

- [x] **A1** — strict law fires only when base-ref resolves to `origin/main`/`main`/release tag; dev landing (fork-point base) passes equal-version-with-bundle-change
- [x] **A2** — non-decrease bottom enforced on both modes: `manifest_version < previous_version ⟹ error`
- [x] **A3** — `train_cut_shared()`, `--no-train` flag, linear-push guard, `train_cut` field all deleted; no train code remains in validator
- [x] **A4** — bats: dev-mode equal-version-with-change passes; release-boundary equal-version-with-change fails; non-decrease enforced; non-train tests unchanged

## Notes

- This is the foundational ticket — tkt-119 (CI) and tkt-120 (docs) depend on its final validator logic
- Detection mechanism for dev vs release mode: inspect whether resolved base-ref is reachable from `origin/main` (release) or is a fork-point/dev-ancestor (integration). Implementation detail; reversible.

## References

- GitHub issue: https://github.com/percena/lattice/issues/117
- Spec: `spc-116` (path above)
- ADR: `ADR-005` → `docs/adr/005-version-bump-at-release-boundary.md`
- Prior: tkt-60 (PR #68), tkt-114 (PR #115)

## Lineage

- Parent spec: **spc-116**
- Parent issue (GH sub-issue): **#116**
- Primary ticket: **tkt-117**
- Covers: **A1, A2, A3, A4**
- Blocked by: (none)
- Parallel group: **G1** (parallel with tkt-118)

## Finish

- pr-125 merged: 2026-08-27T06:51:38Z — https://github.com/percena/lattice/pull/125 (base merge)
- issue #117 closed: 2026-08-27T06:52:21Z — https://github.com/percena/lattice/issues/117
