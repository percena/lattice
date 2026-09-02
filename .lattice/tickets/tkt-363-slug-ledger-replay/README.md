# tkt-363-slug-ledger-replay

> **TL;DR:** Slug-named ledger skipped by replay — stem-as-ticket-id misses binder
> **Kind:** bug · **Priority:** P3
> **Path:** none → tkt-363 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P3 |
| labels | bug, P3 |
| github | https://github.com/percena/lattice/issues/363 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T00:00:00Z |
| updated | 2026-09-02T00:00:00Z |
| adopted | true |
| summary | Derive ticket id via ^tkt-\d+ from stem; backfill tkt-257 pr-open→closed |
| spec | none (post-spc-337 leftover audit) |
| covers | A1, A2 |
| paths | tools/validate-lattice-artifacts.py, skills/_lattice-lib/scripts/transition-api.py, .lattice/.transition-ledger/tkt-257-process-false-success-closure.jsonl |
| **primary_ticket** | tkt-361 (batch primary) |
| **related_tickets** | tkt-361, tkt-362 (same batch PR) |
| **worktree_bind** | tkt-361-spc337-leftover-audit |
| worktree | sibling lattice.worktrees/tkt-361-spc337-leftover-audit/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** Replay derives the ticket id with `^(tkt-\d+)` from the stem (identity + snapshot checks apply to slug-named files); a fixture with a slug-named ledger whose last `to` ≠ binder status fails.
- [ ] **A2** tkt-257's ledger gets its missing pr-open → closed entry (record, trace 'backfill') or is renamed to tkt-257.jsonl with the entry appended — replay green afterwards.

## Approach

Added `re.match(r'^(tkt-\d+|spc-\d+)', stem)` in both `transition-api.py cmd_replay` and `validate-lattice-artifacts.py` to derive `ticket_id` for binder lookup; kept `file_ticket = stem` for identity check. Backfilled tkt-257's missing pr-open → closed entry (pr-268 mergedAt 2026-08-31T04:55:01Z).

## Notes

- Batch PR with tkt-361 (spawn zombie) and tkt-362 (docs residue).

## References

- GitHub issue body is SoT for long prose
- Worktree policy: one tree ↔ one PR; spc|tkt open binds
