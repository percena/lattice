# tkt-431 — spc-427 test coverage follow-up (spc-430)

| field | value |
| --- | --- |
| ticket | tkt-431 |
| issue | #431 |
| spec | spc-430 (parent spc-427) |
| covers | A1, A2 |
| status | closed |
| kind | test |
| priority | P3 |
| created | 2026-09-03T03:24:30Z |
| updated | 2026-09-03T03:24:30Z |

## Why

spc-427 shipped the `_rollback_ledger` unlocked-RMW race fix (A1) and the `lineage-metrics.sh` config.yaml `ratchet_cutoff` shell parse (A3). The v0.5.0 release review found **no automated test guards either**:

- spc-427 A1 acceptance literally promises *"two concurrent recorders + a rollback — the concurrent entry survives"* — no such bats test exists. The existing fault test covers the ledger-**write** failure path, never reaching `_rollback_ledger` (rename-failure path).
- spc-427 A3 shell parse of `config.yaml` (lines 113-117) is untested at the shell level; only the Python `lm.collect(created_after=...)` API is tested.

Both fixes are correct (verified by code reading + 35/24 bats green). Risk = future regression uncaught.

## Scope

- **transition-api.bats** — add rename-failure fault test + concurrent recorder; assert concurrent entry survives rollback.
- **lineage-metrics.bats** — add config.yaml `ratchet_cutoff` shell test (positive + negative degrade).

## Acceptance (mirrors spc-430)

- [x] **A1** rename-failure fault test passes on current code; **fails** if spc-427 A1 lock is removed (regression guard)
- [x] **A2** config.yaml ratchet_cutoff shell test (positive: key present → created_after flows through; negative: key absent → empty → 0/0 backward-compatible) passes
- [x] **A3** full suites green: `bats transition-api.bats` (35+) and `bats lineage-metrics.bats` (24+), no regressions

## Approach

**touch-set:** `skills/_lattice-lib/scripts/tests/transition-api.bats`, `skills/review-lineage/scripts/tests/lineage-metrics.bats`.

1. **A1 test** — set up a binder (tkt-N) with one prior legal transition so `in-progress → parked` is legal. Start a background `python3 "$API" record tkt-N queued in-progress owner reason &` that appends to the ledger. In the foreground, force `os.replace` to fail by replacing the binder file with a directory (so `os.replace(tmp, binder)` raises `IsADirectoryError`/`OSError` → `commit_transaction` calls `_rollback_ledger`). `wait` for the bg recorder. Assert: the bg recorder's entry line is still present in the ledger file (rollback did not clobber it). Regression check: temporarily remove the flock from `_rollback_ledger` → test fails.
2. **A2 test** — plant `$HOME_DIR/config.yaml` with `lineage:\n  ratchet_cutoff: "2021-01-01"`. Run `lineage-metrics.sh --md --no-snapshot --home "$HOME_DIR"` (no `--created-after`). Assert the markdown output or a `--json` snapshot shows `created_after = 2021-01-01` in `coverage_post_ratchet`. Negative: remove the `lineage` key → `created_after` empty → `coverage_post_ratchet` 0/0 (old behavior).

## Anticipated decisions

| point | disposition | note |
| --- | --- | --- |
| rename-failure injection method | agent-decides | replace binder target with a dir (root-uid-independent, same trick as existing line-223 fault test). Reversible, low blast. |
| concurrency timing in bats | agent-decides | `cmd_record &` + `wait`; the flock serializes so the bg entry lands before/after rollback deterministically. |
| config.yaml parse test shape | agent-decides | plant file + run `--md --no-snapshot` + grep output, or `--json` + jq python. |
| regression-guard assertion (fails without lock) | pre-resolved | confirmed in spc-430 Decision 2; the test must fail when the A1 lock is reverted. |

## Decision journal

- 2026-09-03T03:04:37Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #432) [WARN — signal logged, not silently lost]

## Pending decisions

(none — all agent-decides are reversible test-mechanism choices.)

## Ship plan

one-PR, one worktree, one session. No parallel group (N=1).

## Notes

- 2026-09-03 — red-run disposition: lattice-artifacts fail = transient/pre-existing (validator exits 1 on legacy binder timestamp warnings tkt-5..96, predates this PR; tkt-431 binder compliant). bats pass (5m38s). Not introduced by this change.

## Finish

- pr-432 merged: 2026-09-03T03:22:50Z — https://github.com/percena/lattice/pull/432 (base merge)
- issue #431 closed: 2026-09-03T03:23:27Z (reason: completed) — https://github.com/percena/lattice/issues/431
