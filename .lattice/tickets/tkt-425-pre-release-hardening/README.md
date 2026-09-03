# tkt-425-pre-release-hardening

| field | value |
| status | queued |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/425 |
| spec | spc-424 |
| covers | A1, A2, A3, A4, A5, A6 |
| prs | pr-426 — https://github.com/percena/lattice/pull/426 |
| created | 2026-09-03T09:15:00Z |
| updated | 2026-09-03T09:15:00Z |
| wait_reason | (none) |

## Summary

Fix 6 verified correctness/hygiene gaps in the state machine stamp path found during pre-release dev branch review. All fixes are small (~15 lines total), touch disjoint files.

## Scope

- **A1** `finish-stamp.py:281` — when binder already closed + ledger empty, use `open→closed` legacy edge instead of `closed→closed` (illegal)
- **A2** `transition-api.py:~557` — `_rollback_ledger` rollback failure: log to stderr instead of silent `pass`
- **A3** `transition-api.py:646-647` — `cmd_record` finally: wrap `LOCK_UN` + `os.close` in individual try/except (consistency with `_append_ledger_locked`)
- **A4** `ensure-workspace.sh:~660` — status regex `^\| status \|` → `^\| *status *\|` (match L3 hook grammar)
- **A5** `docs/adr/013-*.md` — Status: Proposed → Accepted
- **A6** `.github/workflows/finish-stamp.yml` — add `workflow_dispatch:` with `inputs.pr` + `inputs.repo`

## Acceptance

- [x] A1: finish-stamp.py ledger repair uses `open→closed` when ledger empty + binder already closed (not `closed→closed`)
- [x] A2: _rollback_ledger prints stderr warning on rollback failure (not silent pass)
- [x] A3: cmd_record finally wrapped in try/except (consistent with _append_ledger_locked)
- [x] A4: ensure-workspace.sh status regex matches `|status|` and `| **status** |` (was too strict)
- [x] A5: ADR-013 Status = Accepted
- [x] A6: finish-stamp.yml has workflow_dispatch with inputs.pr + inputs.repo

## Notes

- Pre-release review (2026-09-03) verified all 6 issues against the codebase — no false positives
- Ship plan: one-PR (all fixes disjoint, small)
- A1 fix rationale: `open→closed` is the legal legacy edge (transition_table.py:157); when ledger is completely missing and binder is already closed, we can't know the original prior status — recording a valid entry is better than skipping

## Finish

- (none yet)
