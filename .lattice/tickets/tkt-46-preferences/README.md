# tkt-46-preferences

> **TL;DR:** `.lattice/preferences.md` scaffolded by ensure-lattice from a severity-labeled template, with promotion / supersede lifecycle rules
> **Kind:** feat · **Priority:** P2
> **Path:** spc-42 → tkt-46 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/46 |
| status | closed |
| adopted | false |
| summary | preferences template + ensure-lattice scaffold + lifecycle (promotion ×2, supersede-with-date, Spec/ADR outrank) |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A3 |
| blocked_by | #43 |
| parallel_group | G2 (parallel) |
| paths | skills/_lattice-lib/scripts/ensure-lattice.sh, skills/_lattice-lib/references/templates/preferences.md (new), skills/_lattice-lib/scripts/tests/ensure-lattice.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-46 (this issue) |
| **related_tickets** | tkt-47 (digest promotion-proposal rendering completes A3) |
| **worktree_bind** | tkt-46-preferences |
| worktree | sibling …/lattice.worktrees/tkt-46-preferences/ |
| prs | pr-55 — https://github.com/percena/lattice/pull/55 |

## Acceptance (this slice)

- [x] **A3** (scaffold + lifecycle — this slice delivered by PR #55; digest rendering of promotion proposals remains tkt-47's slice) `ensure-lattice.sh` scaffolds `.lattice/preferences.md` from a template with INVARIANT/DEFAULT/HINT sections per `constraint-language.md`; lifecycle rules recorded in the template header: promotion (decision-journal entry ratified ×2 → proposal in morning digest), supersede-with-date (never delete), Spec/ADR outrank preferences, every use cited in the journal. Digest rendering of promotion proposals is tkt-47's slice.

## Notes

- decision-policy.md (tkt-43) already names `.lattice/preferences.md` in the resolution chain — this ticket makes the file exist
- ensure-lattice must stay idempotent (never overwrite an existing preferences.md)
- HINT prefs apply silently at night; DEFAULT apply + journal; INVARIANT conflicts park (per decision-policy)

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` §3
- Review: `rev-20260826-141124Z` Finding 4

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-46**
- Related / sub-tickets: tkt-47 (A3 completion)
- Covers: **A3** (partial — scaffold/lifecycle)
- Blocked by: **#43**
- Parallel group: **G2 (parallel)**
- Worktree bind: `tkt-46-preferences`
- Child PRs: pr-55 → https://github.com/percena/lattice/pull/55

## Assets

Local files in `./assets/`.

## Finish


- pr-55 merged: 2026-08-26T15:11:30Z — https://github.com/percena/lattice/pull/55 (base merge)
- issue #46 closed: 2026-08-26T15:11:35Z — https://github.com/percena/lattice/issues/46
