# tkt-299 — Test-residue hygiene: writer bats write tkt-7/tkt-9 ledgers into repo home

> **TL;DR:** The 4 writer bats suites write real `.transition-ledger/tkt-7.jsonl`/`tkt-9.jsonl` into the repo home instead of a per-test tmp LATTICE_HOME; A1.5's validator flags the residue locally.
> **Kind:** bug · **Path:** tkt-271 (NOTICED) → tkt-299 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug |
| github | https://github.com/percena/lattice/issues/299 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-01T10:40:00Z |
| updated | 2026-09-01T07:41:01Z |
| adopted | true |
| summary | Route the 4 writer bats suites' ledger writes through a per-test tmp LATTICE_HOME so no residue lands in the repo home. |
| spec | (none — follow-up) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/_lattice-lib/scripts/tests/stamp-pr-open.bats, skills/_lattice-lib/scripts/tests/ratify.bats, skills/_lattice-lib/scripts/tests/bump-fix-cycle.bats, skills/_lattice-lib/scripts/tests/spec-supersede.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-299 (this issue) |
| **related_tickets** | tkt-271 (surfaced the NOTICED) |
| **worktree_bind** | `tkt-299-test-residue-hygiene` |
| prs | pr-304 — https://github.com/percena/lattice/pull/304 |

## Acceptance (this slice)

- [x] The four suites (stamp-pr-open, ratify, bump-fix-cycle, spec-supersede) write ledgers to a per-test tmp `LATTICE_HOME` (like transition-api.bats / reconcile-state.bats), never the repo home.
- [x] No `.transition-ledger/tkt-7.jsonl` / `tkt-9.jsonl` residue after a full suite run.
- [x] `python3 tools/validate-lattice-artifacts.py --home .lattice` is clean (0 transition-ledger findings) on a dev checkout after running the writer suites. — proven: 0 findings; suites green (27/20/17/13); no residue.

## Approach

Each suite already creates a tmp `$REPO` with its own `.lattice/`. The writer scripts resolve the ledger via `LATTICE_HOME` (default `.lattice` relative to cwd). The fix: export `LATTICE_HOME="$REPO/.lattice"` (or the suite's tmp home) for every `run bash "$SPO"/"$SCRIPT" …` invocation so `commit`/`record` write the per-ticket ledger into the tmp repo, not the real repo home. Mirror the `setup()` tmp-home pattern from transition-api.bats.

## Decision journal

- 2026-09-01T07:38:58Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #304) [WARN — signal logged, not silently lost]

## Lineage

- Surfaced by: tkt-271 (NOTICED, 2026-08-31)
- GitHub: #299

## Finish


- pr-304 merged: 2026-09-01T07:40:04Z — https://github.com/percena/lattice/pull/304 (base merge)
- issue #299 closed: 2026-09-01T07:40:27Z (reason: completed) — https://github.com/percena/lattice/issues/299
