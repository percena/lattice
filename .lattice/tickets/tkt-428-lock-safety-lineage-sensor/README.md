# tkt-428-lock-safety-lineage-sensor

| field | value |
| status | closed |
| priority | P3 |
| labels | bug, P3 |
| github | https://github.com/percena/lattice/issues/428 |
| spec | spc-427 |
| covers | A1, A2, A3 |
| prs | pr-429 — https://github.com/percena/lattice/pull/429 |
| created | 2026-09-03T10:30:00Z |
| updated | 2026-09-03T02:19:40Z |
| wait_reason | (none) |

## Summary

Fix 3 pre-existing issues from spc-424 review: _rollback_ledger unlocked RMW race, lock teardown 3x duplication (bare os.close in 2 of 3 sites), lineage-metrics post-ratchet coverage 0/0.

## Scope

- **A1** `transition-api.py:546-556` — `_rollback_ledger`: re-acquire ledger flock before RMW, release after
- **A2** `transition-api.py:368,538,650` — extract `_release_lock_fd(fd)` helper, use in all 3 finally blocks
- **A3** `lineage-metrics.sh` + `.lattice/config.yaml` — read `lineage.ratchet_cutoff` from config, pass to `LM_CREATED_AFTER`

## Acceptance

- [x] A1: _rollback_ledger acquires flock before read, holds through write, releases after
- [x] A2: _release_lock_fd helper exists, called from all 3 sites, no bare os.close remains
- [x] A3: lineage-metrics.sh reads ratchet_cutoff from config.yaml, post-ratchet coverage shows real numbers

## Notes

- Pre-existing issues (not introduced by spc-424), deferred as non-blocking during pre-release review
- A1 fix also addresses the dangling terminal entry issue (rollback is now atomic with lock)
- A2: A3 (spc-424) already fixed cmd_record; this extracts the pattern to a helper and fixes the other 2 sites

## Finish


- pr-429 merged: 2026-09-03T02:18:48Z — https://github.com/percena/lattice/pull/429 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #428 closed: 2026-09-03T02:18:58Z (reason: completed) — https://github.com/percena/lattice/issues/428
