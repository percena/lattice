# tkt-50-batch-night

> **TL;DR:** batch-work becomes a safe night shift — decision/fallback protocols + evidence contract in spawn briefs, watchdog/timebox, batch fuse + graceful drain, `--with-review` chaining review-delivery with a bounded fix loop
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-42 → tkt-50 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/50 |
| status | open |
| adopted | false |
| summary | batch-work night upgrades: brief injection, watchdog, fuse, drain, --with-review + ≤2-cycle fix loop |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A7, A2 |
| blocked_by | #43, #47 |
| parallel_group | G3 (serial-final) |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-50 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-50-batch-night |
| worktree | sibling …/lattice.worktrees/tkt-50-batch-night/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A7** spawn briefs carry decision-policy + fallback-policy + the evidence contract (fresh test output, decision journal, e2e evidence when UI); per-ticket watchdog/timebox marks hung agents `failed`; batch fuse halts subsequent layers when a layer's failure/stuck ratio exceeds the threshold (default 50%, config-tunable) with graceful drain of running agents; `--with-review` chains review-delivery after the last layer and dispatches a bounded (≤2 cycles) implementer-fix loop for material findings before the digest is finalized
- [ ] **A2** (completion) fallback-policy injection into spawn briefs — closes the integration half of tkt-43's A2

## Notes

- Marker gate (`.lattice/.batch-work-active`) unchanged — nights still never merge
- Fuse threshold + timeboxes read from `.lattice/config.yaml` (tunable); RAM gate stays as-is
- Failure isolation currently covers crashes only; watchdog extends it to hangs

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` §5
- Review: `rev-20260826-141124Z` Findings 5, 6

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-50**
- Related / sub-tickets: (none)
- Covers: **A7, A2 (completion)**
- Blocked by: **#43, #47**
- Parallel group: **G3 (serial-final)**
- Worktree bind: `tkt-50-batch-night`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
