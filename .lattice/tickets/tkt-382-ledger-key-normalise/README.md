# tkt-382-ledger-key-normalise

> **TL;DR:** Normalise ledger key to `tkt-N` in `transition-api.py`; fold stray `356.jsonl`/`357.jsonl` into their `tkt-` ledgers; validator guard catches future drift.
> **Kind:** fix (bug) · **Priority:** P2
> **Path:** rev-20260902-080545Z F2 → tkt-382 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/382 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:20:35Z |
| updated | 2026-09-02T11:41:50Z |
| adopted | false |
| summary | transition-api normalises ledger key to tkt-N + validator guard; fold stray ledgers |
| spec | (none — spawned from rev-20260902-080545Z) |
| covers | (none) |
| blocked_by | #381 |
| merge_blocked_by | #381 |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/transition-api.py, tools/validate-lattice-artifacts.py, .lattice/.transition-ledger/ |
| solo_merge | yes |
| primary_ticket | tkt-382 |
| related_tickets | (none) |
| worktree_bind | tkt-382-ledger-key-normalise |
| worktree | sibling `…/<repo>.worktrees/tkt-382-ledger-key-normalise/` |
| prs | pr-394 — https://github.com/percena/lattice/pull/394 |

## Acceptance (this slice)

- [x] **A1** `ledger_path()` normalises bare ids to `tkt-N` (prefix `tkt-` when missing).
- [x] **A2** Validator emits `ledger_key_not_ticket_id` error for non-`tkt-N`-keyed ledger files.
- [x] **A3** `356.jsonl`/`357.jsonl` folded into `tkt-356.jsonl`/`tkt-357.jsonl`; replay opens both files.

## Approach

`ledger_path()` at `transition-api.py:90` formats `{ticket}.jsonl` — it trusts the caller. `356.jsonl`/`357.jsonl` were written with a bare id (the writer could not be identified from the tree). Fix: in `ledger_path()`, prefix `tkt-` when the ticket arg is bare digits. Add validator error `ledger_key_not_ticket_id` in `validate-lattice-artifacts.py` that scans `.transition-ledger/*.jsonl` filenames and flags any not matching `tkt-N.jsonl`. Fold the stray files: merge `356.jsonl` entries into `tkt-356.jsonl` (bind entries must land before existing `in-progress→pr-open` entries), same for `357`.

**Touch-set:** `skills/_lattice-lib/scripts/transition-api.py:90` (`ledger_path`), `tools/validate-lattice-artifacts.py` (new error code), `.lattice/.transition-ledger/356.jsonl` → `tkt-356.jsonl`, `.lattice/.transition-ledger/357.jsonl` → `tkt-357.jsonl`.

## Anticipated decisions

- key normalisation strategy — pre-resolved (rev F2 mechanism): normalise in `ledger_path()`; merge stray files into `tkt-` ledgers.
- validator code name — pre-resolved (rev draft): `ledger_key_not_ticket_id` error.
- fold order — agent-decides: bind entries (`queued→in-progress`) must precede existing `in-progress→pr-open` entries in the merged file.

## Decision journal

## Pending decisions

## Attempts

## Notes

- Blocked by #381 (shared `validate-lattice-artifacts.py` edit — G1 serial).
- Origin: `rev-20260902-080545Z` F2 (lineage-audit baseline, spc-369 dry run).

## References

- GitHub issue: #382
- Review: `rev-20260902-080545Z` Finding F2
- Spec: `spc-369` (review-lineage — produced the finding)
- ADR: `ADR-012` §4 (ledger coverage)

## Lineage

- Parent spec: (none — spawned from review)
- Parent issue: none (ticket-only)
- Primary ticket: tkt-382
- Related / sub-tickets: tkt-381 (blocks this)
- Covers: (none)
- Blocked by: #381
- Merge blocked by: #381
- Parallel group: G1
- Worktree bind: tkt-382-ledger-key-normalise
- Child PRs: (none yet)

## Assets

## Finish

- (none yet)
