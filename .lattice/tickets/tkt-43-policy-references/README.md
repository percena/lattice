# tkt-43-policy-references

> **TL;DR:** decision-policy.md + fallback-policy.md in `_lattice-lib/references` — the total decision-resolution function and bounded-fallback law for unattended agents
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-42 → tkt-43 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/43 |
| status | closed |
| adopted | false |
| summary | decision-policy + fallback-policy references; start-work citation; batch-work injection deferred to tkt-50 |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A1, A2 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/_lattice-lib/references/decision-policy.md (new), skills/_lattice-lib/references/fallback-policy.md (new), skills/start-work/SKILL.md |
| solo_merge | yes |
| **primary_ticket** | tkt-43 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-43-policy-references |
| worktree | sibling …/lattice.worktrees/tkt-43-policy-references/ |
| prs | https://github.com/percena/lattice/pull/52 · pr-52 — https://github.com/percena/lattice/pull/52 |

## Acceptance (this slice)

- [x] **A1** decision-policy.md defines the resolution chain (ticket AC/binder Approach → Spec Decisions → ADR → `.lattice/preferences.md` → default heuristics: codebase convention > minimal public surface > most reversible → park & pivot), the reversibility × blast-radius matrix (reversible+local → self-decide + journal; irreversible or cross-contract → attended PCA / unattended park & pivot), and the journal contract (every self-decision cites its resolution source); start-work references it
- [x] **A2** fallback-policy.md defines pivot-over-retry with the articulated-difference rule (no retry without written cause + delta in `## Attempts`), caps (≤2 tries/path, ≤3 paths/ticket, per-ticket timebox), early-stop signals (same error twice; scope escape beyond ticket `paths`), batch fuse + graceful drain, and stuck-with-ledger framing — content only; batch-work brief injection lands with tkt-50

## Notes

- Both files are new — no overlap with tkt-44/45 (G1 parallel)
- start-work SKILL.md gains load-on-demand rows only (tkt-49 later edits its resume section — serialized by layers)
- ADR-004 §2 (resolution chain) and §5 (bounded loops / stop-with-ledger) are the law these references implement

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` → `docs/adr/004-attention-contract-and-night-shift-delivery.md`
- Review: `rev-20260826-141124Z` Findings 3, 5

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-43**
- Related / sub-tickets: (none)
- Covers: **A1, A2**
- Blocked by: (none)
- Parallel group: **G1 (parallel)**
- Worktree bind: `tkt-43-policy-references`
- Child PRs: [PR #52](https://github.com/percena/lattice/pull/52)

## Assets

Local files in `./assets/`.

## Finish


- pr-52 merged: 2026-08-26T15:10:08Z — https://github.com/percena/lattice/pull/52 (base merge)
- issue #43 closed: 2026-08-26T15:10:14Z — https://github.com/percena/lattice/issues/43
