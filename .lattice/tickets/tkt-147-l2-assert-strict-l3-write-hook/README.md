# tkt-147-l2-assert-strict-l3-write-hook

> **TL;DR:** Harden assert-shippable-cwd under strict to fail non-base-on-main-clone; add PreToolUse Write/Edit hook running assert before shippable writes.
> **Kind:** feat · **Status:** open · **Priority:** P1
> **Path:** spc-145 -> tkt-147 -> (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/147 |
| status | open |
| adopted | false |
| summary | L2 assert strict-flip + L3 PreToolUse Write/Edit hook |
| spec | spc-145 — PreToolUse hard-enforcement stack (path: ../../specs/spc-145-worktree-discipline-gate.md) |
| covers | A4, A5, A7 |
| blocked_by | #146 |
| parallel_group | (serial) |
| paths | `skills/_lattice-lib/scripts/assert-shippable-cwd.sh`, `plugins/lattice/hooks/**`, `plugins/lattice/hooks/hooks.json` |
| solo_merge | yes |
| **primary_ticket** | tkt-146 (ship owner) |
| **related_tickets** | tkt-146, tkt-148 (same PR) |
| **worktree_bind** | `spc-145-worktree-discipline-gate` |
| worktree | sibling `…/lattice.worktrees/spc-145-worktree-discipline-gate/` |
| prs | pr-154 — https://github.com/percena/lattice/pull/154 |

## Acceptance (this slice)

- [x] **A4** `assert-shippable-cwd.sh` under strict fails non-base-on-main-clone; `--allow-base-write --reason` still passes; light profile keeps legacy pass.
- [x] **A5** PreToolUse Write/Edit hook denies shippable writes (`.lattice/**`, product code) when assert fails; `--reason` escape available.
- [x] **A7** New bats pass; existing `assert-shippable-cwd.bats` and `ensure-workspace.bats` still pass (no compliant-path regression).

## Notes

- L3 does NOT trust the L1 sentinel — write-time check is the spoof backstop.
- Path-classifier scope: `.lattice/**` + tracked product code (keep fast).

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-145` (path above)
- ADR: `ADR-006` -> `docs/adr/006-worktree-discipline-hard-enforcement.md`

## Lineage

- Parent spec: **spc-145**
- Parent issue: **#145**
- Primary ticket: **tkt-146**
- Related / sub-tickets: tkt-146, tkt-148
- Covers: **A4, A5, A7**
- Blocked by: **#146**
- Parallel group: (serial)
- Worktree bind: `spc-145-worktree-discipline-gate`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
