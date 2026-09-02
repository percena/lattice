# tkt-335 — finish-ledger flip_close predicate prevents status→closed on merged PRs

> **TL;DR:** flip_close predicate gates status flip on linked-issue verification, but Finish body stamps unconditionally → terminal ledger + non-terminal status
> **Kind:** bug · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug,P1 |
| github | https://github.com/percena/lattice/issues/335 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T02:00:00Z |
| updated | 2026-09-02T02:12:56Z |
| adopted | false |
| summary | finish-ledger flip_close predicate prevents status→closed on merged PRs with linked issue |
| spec | none |
| paths | skills/_lattice-lib/scripts/finish-ledger.sh, skills/_lattice-lib/scripts/tests/finish-ledger.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-335 (this issue) |
| worktree_bind | tkt-335-finish-ledger-flip-close-predicate |
| prs | pr-336 — https://github.com/percena/lattice/pull/336 |

## Acceptance

- [x] **A1** `flip_close` predicate on line 575 of `finish-ledger.sh` changed so a merged PR flips status to `closed` regardless of linked-issue verification (`cancel or merged or issue_closed == "true"`).
- [x] **A2** Regression test in `finish-ledger.bats`: a merged PR with an un-verifiable linked issue (no `--closed-at`, `gh` fails) still flips binder `| status |` to `closed`.
- [x] **A3** Existing test at `finish-ledger.bats` ~line 108 updated to also assert the `| status |` row (not just the "not closed" note line).
- [x] **A4** All existing finish-ledger bats tests still pass.

## Approach

Change the `flip_close` predicate on line 575 of `finish-ledger.sh`:

```python
# before (buggy)
flip_close = cancel or issue_closed == "true" or (not issue_m and merged)
# after (fixed)
flip_close = cancel or merged or issue_closed == "true"
```

Rationale: `merged` is terminal evidence on its own — the validator's `FINISH_MERGED_RE` already treats `pr-N merged:` as terminal. The merge timestamp is firm-verified ISO-8601 by the time this line runs (lines 294-302). The `issue_closed == "true"` term remains for the closed-without-merge path (`--pr-state CLOSED` + a closed issue).

Touch-set:
- `skills/_lattice-lib/scripts/finish-ledger.sh` line 575
- `skills/_lattice-lib/scripts/tests/finish-ledger.bats` — new regression test + update existing test at ~line 108

## Anticipated decisions

- `elif s != orig` direct-write bypass (lines 604-622) — disposition: pre-resolved (no change needed; the one-line fix makes `do_flip=True`, which routes to `commit_transaction` path, so the bypass is never hit for merged PRs).
- Transition table `any → closed` edge — disposition: pre-resolved (already legal in `transition_table.py:122`, so `prepare_commit_text` returns rc=0; no transition-table change needed).
- Should `issue_closed` verification be removed entirely? — disposition: agent-decides (keep for the closed-without-merge path where issue close is the only terminal evidence; remove only from the merged path).

## Decision journal

## Pending decisions

## Attempts

## Notes

- Recurring manual remediation commits: `d17e1ca` (tkt-325/326), `45d18c8` (tkt-327) — both flipped status to `closed` by hand.
- PR #328 (`bacca2f`, issue #323 fix) did NOT touch `flip_close` — it fixed `commit_transaction` IO failure only and explicitly reverted the broad guard.
- No existing test covers "merged + un-verifiable issue → status must flip" (existing test at ~line 108 only asserts a "not closed" note line, not the status row).

## References

- GitHub issue: https://github.com/percena/lattice/issues/335
- Related: #323 (finish-ledger wrong ledger entry + IO failure; code fix shipped in pr-328, did not fix flip_close)
- Validator rule: `tools/validate-lattice-artifacts.py:1459-1471` (`finish_without_terminal_status`)
- ADR: ADR-004 §6 (binder status FSM SoT)

## Finish


- pr-336 merged: 2026-09-02T02:12:07Z — https://github.com/percena/lattice/pull/336 (base merge)
- issue #335 closed: 2026-09-02T02:12:24Z — https://github.com/percena/lattice/issues/335
