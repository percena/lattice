# tkt-381-queue-health-field-row-regex

> **TL;DR:** Fix `_FIELD_ROW_RE` to read 3-column binder rows so 15 `closed |` binders stop vanishing from every count; validator guard prevents the next drift going silent.
> **Kind:** fix (bug) · **Priority:** P2
> **Path:** rev-20260902-080545Z F2 → tkt-381 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/381 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:20:35Z |
| updated | 2026-09-02T17:30:00Z |
| adopted | false |
| summary | queue_health field-row regex reads 3-column rows + validator guard |
| spec | (none — spawned from rev-20260902-080545Z) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/lib/queue_health.py, tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats, skills/_lattice-lib/scripts/tests/ |
| solo_merge | yes |
| primary_ticket | tkt-381 |
| related_tickets | (none) |
| worktree_bind | tkt-381-queue-health-field-row-regex |
| worktree | sibling `…/<repo>.worktrees/tkt-381-queue-health-field-row-regex/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** `_FIELD_ROW_RE` reads 3-column rows: a binder row `| status | closed | ` parses as value `closed`.
- [ ] **A2** Validator emits `binder_row_extra_columns` warning for rows with a stray 3rd column.
- [ ] **A3** Bats fixture: planted 3-column binder asserts `closed` (not `closed |`); existing 2-column rows still pass.

## Approach

`_FIELD_ROW_RE` at `queue_health.py:59` is `r"^\|\s*(?P<field>[A-Za-z_]+)\s*\|\s*(?P<value>.*?)\s*\|\s*$"` — the non-greedy `.*?` up to the last pipe captures `closed |` when a third cell follows. Fix: change the value capture to `[^|]*?` (stop at the next pipe, not the last) and add an optional third-cell suffix `(\|.*)?` to the pattern so the row still matches but the value is the second cell only. Add validator warning `binder_row_extra_columns` in `validate-lattice-artifacts.py` that flags any field row with more than 2 content cells. Plant a bats fixture in `skills/_lattice-lib/scripts/tests/` with a 3-column binder asserting `_parse_field_rows` returns `{"status": "closed"}`.

**Touch-set:** `skills/_lattice-lib/scripts/lib/queue_health.py:59`, `tools/validate-lattice-artifacts.py` (new warning code), `tools/tests/lattice-artifacts.bats` (or `skills/_lattice-lib/scripts/tests/`), new fixture file.

## Anticipated decisions

- regex capture group shape — pre-resolved (rev F2 evidence): `[^|]*?` for value cell; allow trailing 3rd column via optional suffix.
- validator code name — pre-resolved (rev draft): `binder_row_extra_columns` warning.
- fixture placement — agent-decides: `skills/_lattice-lib/scripts/tests/` (codebase convention; `binder_rows.py` tests live there).

## Decision journal

## Pending decisions

## Attempts

## Notes

- 15 legacy binders with 3-column rows will trigger the new warning — they go into the baseline, not re-rowed here (ADR-012 §7 front-matter migration is a later Spec).
- Origin: `rev-20260902-080545Z` F2 (lineage-audit baseline, spc-369 dry run).

## References

- GitHub issue: #381
- Review: `rev-20260902-080545Z` Finding F2
- Spec: `spc-369` (review-lineage — produced the finding)
- ADR: `ADR-012` §4 (ledger coverage as conformance sensor), §7 (binder front matter — later Spec)

## Lineage

- Parent spec: (none — spawned from review)
- Parent issue: none (ticket-only)
- Primary ticket: tkt-381
- Related / sub-tickets: tkt-382 (blocked_by this)
- Covers: (none)
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G1
- Worktree bind: tkt-381-queue-health-field-row-regex
- Child PRs: (none yet)

## Assets

## Finish

- (none yet)
