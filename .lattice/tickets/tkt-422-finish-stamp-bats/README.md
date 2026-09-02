| field | value |
| status | queued |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/422 |
| spec | spc-416 |
| covers | A9 |
| prs | (none) |
| created | 2026-09-02T16:30:00Z |
| updated | 2026-09-02T16:30:00Z |
| wait_reason | (none) |

## Summary

Dedicated `finish-stamp.bats` test suite that calls `finish-stamp.py` directly (not via finish-ledger.sh), covering all 5 dry-run scenarios from spc-416 A9. tkt-418 shipped finish-stamp.py without the test suite; this fills the gap.

## Scope

- `skills/_lattice-lib/scripts/tests/finish-stamp.bats` — 5 test scenarios calling finish-stamp.py CLI directly
- Each test sets up a temp repo with a binder + ledger, runs finish-stamp.py with overrides (--merged-at, --pr-state, --pr-url), and asserts on binder/ledger state + exit code

## Acceptance

- [ ] A9: finish-stamp.bats covers all 5 dry-run scenarios:
  1. Normal (pr-open→closed) — status flips, ledger has pr-open→closed
  2. Direct jump (in-progress→closed) — status flips, ledger has in-progress→closed, anomaly line
  3. Idempotent (already closed → no-op) — no change, nothing staged, exit 0
  4. Mode C repair (missing edge → insert + stamp) — missing intermediate edge inserted before →closed
  5. Staging failure (gitignored → exit non-zero) — git add fails, exit non-zero (A5)

## Approach

- Follow the existing `finish-ledger.bats` pattern: temp repo (`mktemp -d`), mini `.lattice/tickets/tkt-N-slug/README.md` binder, `.lattice/.transition-ledger/tkt-N.jsonl` ledger
- Call `finish-stamp.py` directly with `--binder <path> --pr N --merged-at <ts> --pr-state MERGED --pr-url <url>` (bypasses finish-ledger.sh front-end)
- Assert on binder `| status |` row, ledger JSONL content, `git diff --cached --name-only` staging, and exit code
- Scenario 4 (Mode C): pre-seed ledger with a `queued→in-progress` edge but leave binder at `pr-open` (gap) → finish-stamp.py should insert `in-progress→pr-open` before stamping `→closed`
- Scenario 5 (staging failure): add `.transition-ledger/` to `.gitignore` in the temp repo → `git add` fails → assert exit non-zero

## Anticipated decisions

- Test fixture: temp dirs with mini `.lattice/` tree (follow finish-ledger.bats pattern) — **pre-resolved**
- CLI subprocess vs Python import: CLI subprocess (bats shells out) — **pre-resolved**
- Ledger home resolution: `home_for_binder` resolves from binder path; temp repo's `.lattice/` is the home — **pre-resolved**

## Notes

- Blocked by nothing — finish-stamp.py is shipped (tkt-418, PR #420) + A3-fixed (tkt-419, PR #421).
- Existing finish-ledger.bats tests 29-58 exercise finish-stamp.py indirectly; this suite tests it in isolation.
- A3 idempotency fix (tkt-419) is specifically verified by scenario 3.
