# tkt-13-duplicate-work-precheck

> **TL;DR:** New check-duplicate-work.sh script in _lattice-lib + integration into create-tickets and start-work pre-flight
> **Kind:** feat · **Status:** closed · **Priority:** P2
> **Path:** spc-12 → tkt-13 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/13 |
| status | closed |
| adopted | false |
| summary | duplicate-work precheck script + create-tickets/start-work integration |
| spec | spc-12 — Lattice skill-gap bridge (path: ../../specs/spc-12-skill-gap-bridge.md) |
| covers | A1 |
| blocked_by | (none) |
| parallel_group | G2 (serial) |
| paths | _lattice-lib/scripts/check-duplicate-work.sh, skills/create-tickets/SKILL.md, skills/start-work/SKILL.md |
| solo_merge | yes (primary of one-PR with tkt-14) |
| **primary_ticket** | tkt-13 (this issue) |
| **related_tickets** | tkt-14 (bug repro loop, same PR) |
| **worktree_bind** | tkt-13-duplicate-work-precheck |
| worktree | sibling …/lattice.worktrees/tkt-13-duplicate-work-precheck/ |
| prs | pr-19 — https://github.com/percena/lattice/pull/19 |

## Acceptance (this slice)

- [x] **A1** `check-duplicate-work.sh` exists in `_lattice-lib/scripts/`, checks 3 surfaces (open GitHub issues via `gh issue list`, local worktrees via `git worktree list`, open PRs via `gh pr list`), uses semantic title matching (≥2 shared significant tokens or CJK run ≥3 chars), always advisory (exits 0), and is integrated into create-tickets pre-flight and start-work pre-flight

## Notes

- Shares start-work/SKILL.md path with tkt-14 (bug repro loop) → one-PR, one worktree
- This ticket is the primary of that one-PR; tkt-14 rides as related_ticket
- ADR-002 §1: GitHub-native (3 surfaces, not ERP's 4-surface Firestore hybrid)

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-12` (path above)
- ADR: `ADR-002` → `docs/adr/002-lattice-skill-gap-bridge-adaptations.md`
- Review: `rev-20260825-072540Z` Finding 1
- ERP reference: `FlowDance ERP skill: request-feature/SKILL.md` (check-duplicate-work.mjs pattern)

## Lineage

- Parent spec: **spc-12**
- Parent issue (GH sub-issue): **#12**
- Primary ticket: **tkt-13**
- Related / sub-tickets: **tkt-14** (same PR)
- Covers: **A1**
- Blocked by: (none)
- Parallel group: **G2 (serial)**
- Worktree bind: `tkt-13-duplicate-work-precheck`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish


- pr-19 merged: 2026-08-25T08:42:46Z — https://github.com/percena/lattice/pull/19 (base merge)
- issue #13 closed: 2026-08-25T08:42:52Z — https://github.com/percena/lattice/issues/13
