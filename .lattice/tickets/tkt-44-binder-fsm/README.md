# tkt-44-binder-fsm

> **TL;DR:** Binder template gains Approach / Anticipated decisions / Decision journal / Pending decisions / Attempts sections; field-table `status` extended into the FSM enum; validator checks transitions
> **Kind:** feat · **Status:** pr-open · **Priority:** P2
> **Path:** spc-42 → tkt-44 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/44 |
| status | pr-open |
| adopted | false |
| summary | binder sections + status FSM enum (compatible with finish-ledger closed stamp) + validator transition checks |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A4 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/create-tickets/references/templates/ticket-binder.md, tools/validate-lattice-artifacts.py, tools/tests/ |
| solo_merge | yes |
| **primary_ticket** | tkt-44 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-44-binder-fsm |
| worktree | sibling …/lattice.worktrees/tkt-44-binder-fsm/ |
| prs | pr-54 — https://github.com/percena/lattice/pull/54 |

## Acceptance (this slice)

- [x] **A4** Binder template gains `## Approach`, `## Anticipated decisions` (disposition `pre-resolved | agent-decides | must-ask`), `## Decision journal`, `## Pending decisions`, `## Attempts`; existing field-table `status` extended in place — working `queued | in-progress | parked | stuck | pr-open | rework | deferred`, terminal `closed` (merged vs closed-without-merge read from `## Finish` mergedAt, compatible with finish-ledger.sh), legacy `open` accepted with a validator warning; `validate-lattice-artifacts.py` rejects unknown status values and illegal transitions (e.g. `closed` without a `## Finish` ledger)

## Notes

- Do NOT touch finish-ledger.sh semantics — `closed` stays its terminal stamp; this ticket only widens the accepted working states
- Lazy migration: existing binders with `open` warn, not fail
- tkt-48 (create-tickets scan) consumes these sections — blocked_by this ticket

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` §6
- Review: `rev-20260826-141124Z` Finding 7 (observability)

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-44**
- Related / sub-tickets: (none)
- Covers: **A4**
- Blocked by: (none)
- Parallel group: **G1 (parallel)**
- Worktree bind: `tkt-44-binder-fsm`
- Child PRs: pr-54 (https://github.com/percena/lattice/pull/54)

## Assets

Local files in `./assets/`.

## Finish


- pr-54 merged: 2026-08-26T15:10:50Z — https://github.com/percena/lattice/pull/54 (base merge)
- issue #44 closed: 2026-08-26T15:10:56Z — https://github.com/percena/lattice/issues/44
