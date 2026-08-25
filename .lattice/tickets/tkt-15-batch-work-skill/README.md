# tkt-15-batch-work-skill

> **TL;DR:** New batch-work skill — DAG orchestration on sibling worktrees using parallel_group + independence gates
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-12 → tkt-15 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/15 |
| status | open |
| adopted | false |
| summary | batch-work skill — DAG orchestration on sibling worktrees + BATCH_WORK=1 merge block |
| spec | spc-12 — Lattice skill-gap bridge (path: ../../specs/spc-12-skill-gap-bridge.md) |
| covers | A2 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/batch-work/SKILL.md (new), possibly _lattice-lib/scripts/ |
| solo_merge | yes |
| **primary_ticket** | tkt-15 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-15-batch-work-skill |
| worktree | sibling …/lattice.worktrees/tkt-15-batch-work-skill/ |
| prs | (none) |

## Acceptance (this slice)

- [x] **A2** `batch-work` skill exists with `--ids`/`--groups` input, reads `parallel_group` from ticket binders, spawns one worktree per tkt via `ensure-workspace.sh`, layer-barrier sync (waits for all agents in a group before next), `BATCH_WORK=1` env blocks finish-work merge (agents create-pr only), RAM threshold check before spawn, dry-run mode, failure isolation (one agent crash doesn't block peers or subsequent layers)

## Notes

- Independent of tkt-13/14 (G1 parallel, own PR, own worktree)
- ADR-002 §3: reuses Lattice sibling worktree model, NOT ERP's Firestore-based DAG
- BATCH_WORK=1 blocks finish-work merge (safety: only create-pr, human reviews then finish-work)
- May reference tkt-13's check-duplicate-work.sh for pre-spawn dedup (soft dependency, not blocked_by)

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-12` (path above)
- ADR: `ADR-002` → `docs/adr/002-lattice-skill-gap-bridge-adaptations.md`
- Review: `rev-20260825-072540Z` Finding 2
- ERP reference: `/Users/mxue/GitRepos/FlowDance/erp/.claude/skills/batch-implement/SKILL.md`

## Lineage

- Parent spec: **spc-12**
- Parent issue (GH sub-issue): **#12**
- Primary ticket: **tkt-15**
- Related / sub-tickets: (none)
- Covers: **A2**
- Blocked by: (none)
- Parallel group: **G1 (parallel)**
- Worktree bind: `tkt-15-batch-work-skill`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
