# tkt-80-prs-row-cleanup

> **TL;DR:** Canonicalize the 13 legacy prs rows flagged by the new prs_row_format warning — format only, facts untouched, warnings to zero
> **Kind:** chore · **Priority:** P3
> **Path:** (ticket-only) → tkt-80 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/80 |
| status | pr-open |
| adopted | false |
| summary | 13 binder prs rows → canonical `pr-N — <URL>`; zero prs_row_format warnings |
| spec | none — digest finding (rev-20260826-172600Z F1) |
| covers | digest F1 |
| blocked_by | #74 (the warning must be merged so the zero-count is verifiable) |
| parallel_group | G1 (parallel) |
| paths | .lattice/tickets/tkt-6-*/README.md, tkt-7-*, tkt-10-*, tkt-31-*, tkt-32-*, tkt-33-*, tkt-34-*, tkt-35-review-code-extended-axes/, tkt-35-split-lint-heavy/, tkt-40-*, tkt-45-*, tkt-46-*, tkt-49-*, tkt-50-* (flagged rows only) |
| solo_merge | yes |
| **primary_ticket** | tkt-80 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-80-prs-row-cleanup |
| worktree | sibling …/lattice.worktrees/tkt-80-prs-row-cleanup/ |
| prs | pr-86 — https://github.com/percena/lattice/pull/86 |

## Acceptance (this slice)

- [x] `validate-lattice-artifacts` emits 0 prs_row_format warnings repo-wide
- [x] Row facts unchanged — format-only edits (comma-join multiples per tkt-74 grammar; genuine `(none…)` placeholders untouched)

## Approach

Run the validator, collect the exact flagged rows, rewrite each to `pr-N — <URL>` (comma-joined when multiple), keeping any factual annotations by moving them to the binder's Notes if worth keeping. Re-run to zero. No GH calls needed — URLs already present in the rows.

## Anticipated decisions

- A row whose PR reference is genuinely ambiguous — disposition: agent-decides (verify via `gh pr view` read-only; journal)

## Decision journal

- 2026-08-27 — tkt-10 prs row was bare `pr-11` with no URL (the one row lacking a self-contained URL). Verified read-only via `gh pr view 11`: MERGED, "docs: refine README positioning + add Acknowledgements" — matches the ticket. Appended the canonical URL. (Chain: binder Anticipated decisions → agent-decides.)
- 2026-08-27 — tkt-6/tkt-7 rows carried annotation `(none — rides tkt-5 PR)`. Dropped rather than moved to Notes: both binders' Notes already state the ticket lands inside the tkt-5 PR, so moving it would duplicate. Verified read-only via `gh pr view 9`: MERGED, "chore(ci): land v7 action bumps + Dependabot grouping + ADR-001 (spc-4)" — confirms pr-9 is the tkt-5 combined PR.
- 2026-08-27 — Other prefixes dropped (`(none) · `, `#37 · `, duplicate bare URL before ` · `): stale placeholders/duplicates of the canonical entry that follows, zero factual content — format-only removal per ticket scope.

## Pending decisions

## Attempts

## Notes

- blocked_by #74 is about verifiability (the warning ships with it); if #74 merged already, base has it — check at start

## References

- Digest: `rev-20260826-172600Z` Finding 1

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-80** · Parallel group: **G1** · Worktree bind: `tkt-80-prs-row-cleanup`

## Finish

- (none yet)
