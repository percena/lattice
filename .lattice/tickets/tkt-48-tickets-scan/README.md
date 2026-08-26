# tkt-48-tickets-scan

> **TL;DR:** create-tickets runs an anticipated-decisions dry-run per ticket and authors `## Approach` (sketch + touch-set) at split time — front-loading the night's questions
> **Kind:** feat · **Status:** pr-open · **Priority:** P2
> **Path:** spc-42 → tkt-48 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/48 |
| status | pr-open |
| adopted | false |
| summary | anticipated-decisions scan (pre-resolved / agent-decides / must-ask) + Approach authoring in create-tickets |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A5 |
| blocked_by | #44 |
| parallel_group | G2 (parallel) |
| paths | skills/create-tickets/SKILL.md, skills/create-tickets/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-48 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-48-tickets-scan |
| worktree | sibling …/lattice.worktrees/tkt-48-tickets-scan/ |
| prs | pr-56 — https://github.com/percena/lattice/pull/56 |

## Acceptance (this slice)

- [x] **A5** create-tickets runs an anticipated-decisions scan per proposed ticket (dry-run against real code, emit decision points with dispositions `pre-resolved | agent-decides | must-ask` into the binder `## Anticipated decisions`) and authors `## Approach` (5–10 line sketch + touch-set) at split time; pre-resolved items join the single delivery-meta batch — no serial questioning

## Notes

- Binder sections come from tkt-44 (blocked_by)
- Scan stays inside the one-batch delivery-meta rule — dispositions are presented with the ship plan, not as extra rounds
- Does not touch templates/ (tkt-44's path) — SKILL.md + flow.md only

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` §2
- Review: `rev-20260826-141124Z` Finding 2

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-48**
- Related / sub-tickets: (none)
- Covers: **A5**
- Blocked by: **#44**
- Parallel group: **G2 (parallel)**
- Worktree bind: `tkt-48-tickets-scan`
- Child PRs: pr-56 — https://github.com/percena/lattice/pull/56

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
