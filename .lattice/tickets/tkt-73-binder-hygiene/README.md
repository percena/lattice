# tkt-73-binder-hygiene

> **TL;DR:** Migrate 5 legacy `open` binders to FSM terminal states from GH facts; canonicalize tkt-43/tkt-5 prs rows; zero binder validator warnings
> **Kind:** chore · **Priority:** P3
> **Path:** (ticket-only) → tkt-73 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/73 |
| status | pr-open |
| adopted | false |
| summary | legacy binder FSM migration (tkt-8/13/14/15/16) + prs-row canonicalization (tkt-43, tkt-5) |
| spec | none — hygiene from round-1/2 digests |
| covers | digest observations (rev-20260826-145922Z, rev-20260826-160233Z) |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | .lattice/tickets/tkt-8-*/README.md, .lattice/tickets/tkt-13-*/README.md, .lattice/tickets/tkt-14-*/README.md, .lattice/tickets/tkt-15-*/README.md, .lattice/tickets/tkt-16-*/README.md, .lattice/tickets/tkt-43-*/README.md, .lattice/tickets/tkt-5-*/README.md |
| solo_merge | yes |
| **primary_ticket** | tkt-73 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-73-binder-hygiene |
| worktree | sibling …/lattice.worktrees/tkt-73-binder-hygiene/ |
| prs | pr-78 — https://github.com/percena/lattice/pull/78 |

## Acceptance (this slice)

- [x] `validate-lattice-artifacts` emits 0 legacy/status warnings for `.lattice/tickets/`
- [x] tkt-43 and tkt-5 prs rows canonical (`pr-N — <URL>`); all migrated binders' `## Finish` content sourced from GH facts only (finish-ledger.sh or `gh pr view`) — nothing invented

## Approach

For each of the 5 legacy binders: `gh pr view` / `gh issue view` the linked PR/issue to confirm merged/closed facts; where a real `## Finish` ledger is missing, stamp via `finish-ledger.sh --pr N --issue M --binder <path>` (idempotent, reads GH itself); set field-table `status: closed`. Then fix the two prs rows by hand to canonical form. Re-run the validator until binder warnings hit zero. Read-only against GitHub — no issue/PR mutations.

## Anticipated decisions

- A binder whose PR facts are ambiguous (e.g. closed-without-merge) — disposition: agent-decides (record exactly what GH says; `closed` only when the closing issue actually closed, per finish-ledger semantics)

## Decision journal

- tkt-8 has no delivery PR (cleanup ticket: closes Dependabot #1/#2/#3) and `finish-ledger.sh` requires `--pr` → hand-wrote its `## Finish` from `gh pr view 1/2/3` + `gh issue view 8` facts (PRs closed-not-merged 2026-08-01, issue #8 closed COMPLETED 2026-08-01T10:31:34Z). Source: binder Approach + "invent nothing" rule; reversible/local.
- finish-ledger.sh appended `pr-N — URL` to prs rows without removing the `(none)` placeholder → stripped `(none) · ` by hand in tkt-13/14/15/16 (acceptance requires canonical rows). Helper wart noted, not fixed here (out of paths).
- tkt-5 prs-row notes `(base dev, all CI green)` dropped rather than moved to Notes — CI-green is already recorded by its A4 checkbox; nothing factual lost. Reversible/local.
- Header-blockquote `**Status:** open` → `closed` in the 7 in-scope binders (stale vs field-table SoT); the same decorative label exists in ~25 binders repo-wide — left untouched (out of paths).
- tkt-8 prs row left as `(none — closes #1/#2/#3)` — truthful; canonical `pr-N — URL` form applies only to rows that reference an actual PR.

## Pending decisions

## Attempts

## Notes

- finish-ledger.sh refuses OPEN PRs and foreign repos — rely on its guards rather than re-implementing
- Do not touch any binder outside the 7 listed paths

## References

- Digests: `rev-20260826-145922Z` §notes, `rev-20260826-160233Z` §4

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-73** · Parallel group: **G1** · Worktree bind: `tkt-73-binder-hygiene`

## Finish


- pr-78 merged: 2026-08-27T02:11:50Z — https://github.com/percena/lattice/pull/78 (base merge)
- issue #73 closed: 2026-08-27T02:11:55Z — https://github.com/percena/lattice/issues/73
