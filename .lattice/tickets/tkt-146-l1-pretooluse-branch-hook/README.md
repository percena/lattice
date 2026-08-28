# tkt-146-l1-pretooluse-branch-hook

> **TL;DR:** Location-based PreToolUse Bash hook denies raw git branch-create/switch in the main clone; ensure-workspace sentinel prevents self-block.
> **Kind:** feat · **Status:** open · **Priority:** P1
> **Path:** spc-145 -> tkt-146 -> (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/146 |
| status | open |
| adopted | false |
| summary | L1 PreToolUse hook blocks raw branch ops in main clone + ensure-workspace sentinel |
| spec | spc-145 — PreToolUse hard-enforcement stack (path: ../../specs/spc-145-worktree-discipline-gate.md) |
| covers | A1, A2, A3, A8 |
| blocked_by | (none — foundation) |
| parallel_group | (serial) |
| paths | `plugins/lattice/hooks/**`, `plugins/lattice/hooks/hooks.json`, `skills/_lattice-lib/scripts/ensure-workspace.sh` |
| solo_merge | yes |
| **primary_ticket** | tkt-146 (this issue) — owner of the one-PR ship |
| **related_tickets** | tkt-147, tkt-148 (same PR) |
| **worktree_bind** | `spc-145-worktree-discipline-gate` (one-PR serial; rebinding to tkt-146 optional) |
| worktree | sibling `…/lattice.worktrees/spc-145-worktree-discipline-gate/` |
| prs | (none yet) |

## Acceptance (this slice)

- [x] **A1** Raw `git checkout -b <name>` and `git switch -c <name>` in the main clone (bound or unbound) is denied with a message pointing to ensure-workspace / /start-work.
- [x] **A2** `git branch <create>` + `git switch <existing>` (two-step bypass) is also denied in the main clone.
- [x] **A3** `ensure-workspace --mode worktree --bind tkt|spc …` runs its internal git branch/worktree/checkout without self-block (sentinel passthrough); worktree created; agent can cd and write.
- [x] **A8** Switching to a base branch (main/dev/master) in the main clone is never blocked.

## Notes

- Gate on **location**, not branch name (bound name in main clone is still drift). Sentinel = env var `LATTICE_WORKSPACE_OK=1`, set by ensure-workspace before its own git branch/checkout. L3 Write hook (tkt-147) does NOT trust this sentinel.

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-145` (path above)
- ADR: `ADR-006` -> `docs/adr/006-worktree-discipline-hard-enforcement.md`

## Lineage

- Parent spec: **spc-145**
- Parent issue (GH sub-issue of Spec primary): **#145**
- Primary ticket: **tkt-146**
- Related / sub-tickets: tkt-147, tkt-148
- Covers: **A1, A2, A3, A8**
- Blocked by: (none)
- Parallel group: (serial)
- Worktree bind: `spc-145-worktree-discipline-gate`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
