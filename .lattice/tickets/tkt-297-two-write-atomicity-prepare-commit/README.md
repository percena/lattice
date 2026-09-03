# tkt-297 — Two-write atomicity: prepare_commit_text for in-lock single-write

> **TL;DR:** Extract `prepare_commit_text()` + `commit_transaction()` from `commit` so the 5 writers mutate the binder once (status + non-status + journal + ledger in one locked transaction), curing the bump-fix-cycle double-increment + writer concurrency windows.
> **Kind:** bug · **Path:** tkt-271 (pr-296 review) → tkt-297 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug |
| github | https://github.com/percena/lattice/issues/297 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-01T11:00:00Z |
| updated | 2026-09-01T09:08:22Z |
| adopted | true |
| summary | Writers call prepare_commit_text+commit_transaction in-lock for one atomic binder mutation (no two-write window). |
| spec | (none — follow-up) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/_lattice-lib/scripts/transition-api.py, skills/_lattice-lib/scripts/{stamp-pr-open,finish-ledger,ratify,spec-supersede,bump-fix-cycle}.sh |
| solo_merge | yes |
| **primary_ticket** | tkt-297 (this issue) |
| **related_tickets** | tkt-271 (surfaced) |
| **worktree_bind** | `tkt-297-two-write-atomicity-prepare-commit` |
| prs | pr-312 — https://github.com/percena/lattice/pull/312 |

## Acceptance (this slice)

- [x] `transition-api.py` exposes `prepare_commit_text(orig_text, …)` (pure, no disk I/O) returning `(rc, new_text, entry)` + `commit_transaction(binder, new_text, entry)` (disk-IO: temp + ledger + atomic rename + A1.2 rollback).
- [x] The 5 writers call them inside their dir-lock so the binder is mutated ONCE (status + non-status fields + journal + `updated` + ledger in one transaction) — no two-write window.
- [x] bump-fix-cycle's pr-open→rework flip is now single-write atomic (fix_cycles bump + status + journal + ledger together) — the double-increment-on-crash regression is cured (crash leaves neither, re-run is idempotent).
- [x] No `record`/direct-stamp bypass remains in canonical writer status paths; the `commit` CLI is unchanged for non-writer callers (coordinator).
- [x] Green: transition-api 26, stamp-pr-open 27, finish-ledger 50, ratify 20, spec-supersede 13, bump-fix-cycle 17, reconcile-state 31, transition-parity 8, guard 65 clean, py_compile OK, shellcheck info-only.

## Approach

Refactor `_commit_locked` into `prepare_commit_text` (pure: read prior from orig_text, validate edge+escape+coupled wait_reason+continuity, build entry + new_text with status/wait_reason/updated/journal flipped) + `commit_transaction` (disk-IO: temp + chmod + ledger append + atomic rename + rollback). Each writer's python heredoc imports `_ta` (transition-api via importlib), does its non-status mutations, calls `prepare_commit_text(mutated, …)` + `commit_transaction(binder, nt, entry)` under its dir lock — removing the bash `commit` call + the `@@TRANSITION_FROM`/`@@JOURNAL_B64`/`@@STAMP` IPC. bump-fix-cycle's rework→rework escape (not a legal edge) keeps the single in-python write (fix_cycles+journal, no prepare/commit).

## Decision journal

- 2026-09-01 — prepare_commit_text returns `(rc, new_text, entry)` (rc 0/1/2/3 mirroring the CLI) so writers can branch on refusal without parsing stderr. commit_transaction preserves the binder mode + A1.2 fail-close ordering. The `committed:` line is stripped from writer stdout (tests assert the writer's own messages).
- 2026-09-01T09:07:14Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #312) [WARN — signal logged, not silently lost]

## Lineage

- Surfaced by: tkt-271 (pr-296 review)
- GitHub: #297

## Finish


- pr-312 merged: 2026-09-01T09:07:42Z — https://github.com/percena/lattice/pull/312 (base merge)
- issue #297 closed: 2026-09-01T09:07:56Z (reason: completed) — https://github.com/percena/lattice/issues/297
