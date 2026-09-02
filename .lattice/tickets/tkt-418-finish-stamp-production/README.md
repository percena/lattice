| field | value |
| status | closed |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/418 |
| spec | spc-416 |
| covers | A1, A2, A3, A4, A5, A7, A8, A9 |
| prs | pr-420 — https://github.com/percena/lattice/pull/420 |
| updated | 2026-09-02T15:40:25Z |
| wait_reason | (none) |

## Summary

Harden finish-stamp.py from dry-run prototype to production. Write finish-stamp.bats test suite. Deprecate finish-ledger.sh (legacy entrypoint delegates to finish-stamp.py). Update finish-work SKILL.md step 11.

## Scope

- Production harden finish-stamp.py (cancel path, GHE hostname, error UX)
- finish-stamp.bats: 5 scenarios (normal, direct jump, idempotent, Mode C, staging failure)
- finish-ledger.sh: delegate to finish-stamp.py (backward-compatible)
- finish-work SKILL.md: step 11 uses finish-stamp.py
- spc-297 acceptance note: finish path no longer uses commit_transaction

## Acceptance

- [ ] A1: pure Python single-process stamp (no bash/Python boundary)
- [ ] A2: correct edge from actual prior status (no hardcoded pr-open→closed)
- [ ] A3: idempotent (no-op when already closed)
- [ ] A4: Mode C repair (insert missing intermediate ledger edges)
- [ ] A5: staging fails LOUD (exit non-zero, no || true)
- [ ] A7: finish-work SKILL.md step 11 updated
- [ ] A8: finish-ledger.sh delegates to finish-stamp.py
- [ ] A9: finish-stamp.bats covers all 5 dry-run scenarios

## Notes

- Prototype at skills/_lattice-lib/scripts/finish-stamp.py passed 22/22 dry-run assertions
- commit_transaction stays in transition-api.py for other callers (stamp-pr-open.sh, bump-fix-cycle.sh)

## Finish

- pr-420 merged: 2026-09-02T14:09:58Z — https://github.com/percena/lattice/pull/420 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #418 closed: 2026-09-02T14:11:30Z (reason: completed) — https://github.com/percena/lattice/issues/418
