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
| status | queued |
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
| prs | (none) |

## Acceptance (this slice)

- [ ] `validate-lattice-artifacts` emits 0 legacy/status warnings for `.lattice/tickets/`
- [ ] tkt-43 and tkt-5 prs rows canonical (`pr-N — <URL>`); all migrated binders' `## Finish` content sourced from GH facts only (finish-ledger.sh or `gh pr view`) — nothing invented

## Approach

For each of the 5 legacy binders: `gh pr view` / `gh issue view` the linked PR/issue to confirm merged/closed facts; where a real `## Finish` ledger is missing, stamp via `finish-ledger.sh --pr N --issue M --binder <path>` (idempotent, reads GH itself); set field-table `status: closed`. Then fix the two prs rows by hand to canonical form. Re-run the validator until binder warnings hit zero. Read-only against GitHub — no issue/PR mutations.

## Anticipated decisions

- A binder whose PR facts are ambiguous (e.g. closed-without-merge) — disposition: agent-decides (record exactly what GH says; `closed` only when the closing issue actually closed, per finish-ledger semantics)

## Decision journal

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

- (none yet)
