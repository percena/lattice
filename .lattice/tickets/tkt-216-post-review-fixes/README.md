# tkt-216-post-review-fixes

> **TL;DR:** Fix 4 HIGH + 2 MEDIUM bugs found in dev branch review of spc-186/spc-212 batch
> **Kind:** fix · **Priority:** P1
> **Path:** (standalone) → tkt-216 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/216 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-29T16:30:00Z |
| updated | 2026-08-29T17:00:00Z |
| adopted | false |
| summary | Post-review fix batch: ensure-python3 test regressions, tracked batch marker, queue_health banner bug, ci-gate flock, stale spc-187 refs, JSON escaping |
| covers | A1, A2, A3, A4, A5, A6, A7, A8 |
| blocked_by | (none) |
| paths | skills/_lattice-lib/scripts/**, skills/finish-work/scripts/**, .lattice/.batch-work-active, .gitignore, plugins/lattice/hooks/lib/**, skills/batch-work/**, skills/finish-work/** |
| solo_merge | yes |
| primary_ticket | tkt-216 (this issue) |
| related_tickets | (none) |
| worktree_bind | tkt-216-post-review-fixes |
| worktree | sibling …/lattice.worktrees/tkt-216-post-review-fixes/ |
| prs | pr-217 — https://github.com/percena/lattice/pull/217 |
| found_by | review |

## Acceptance (this slice)

- [ ] **A1** `reconcile-state.bats` "gh not installed" test passes (exit 2)
- [ ] **A2** `close-fixed-issues.bats` "missing extractor lib" test passes (exit 2)
- [ ] **A3** `.batch-work-active` not tracked; added to `.gitignore`
- [ ] **A4** `queue_health.py` banner has no spurious separator
- [ ] **A5** `ci-gate-check.sh` binder write uses `fcntl.flock`
- [ ] **A6** `grep -rn spc-187` returns zero hits across codebase
- [ ] **A7** `arr_json()` escapes both backslash and double-quote
- [ ] **A8** Full bats test suite passes (no regressions)

## Approach

1. **A1/A2 — ensure-python3 test fix:** Add `dirname` to the restricted test PATHs in `reconcile-state.bats`; for `close-fixed-issues.bats`, also symlink `ensure-python3.sh` so the relative path resolves from the temp dir.
2. **A3 — untrack batch marker:** `git rm --cached .lattice/.batch-work-active` + add to `.gitignore`.
3. **A4 — banner fix:** Remove the standalone `" · " +` in `queue_health.py:268`.
4. **A5 — flock in ci-gate-check:** Add `fcntl.flock(lock_fd, fcntl.LOCK_EX)` / `LOCK_UN` pattern around the binder read-modify-write in `ci-gate-check.sh`.
5. **A6 — spc-187 sweep:** `sed -i 's/spc-187/spc-186/g'` across all affected files.
6. **A7 — JSON escaping:** Add double-quote escaping to `arr_json()` in `check-installed-skill-drift.sh`.

Touch-set: ~15 files across scripts, tests, skills docs.

## Anticipated decisions

- ensure-python3 test fix approach: add dirname to test PATH vs. guard dirname in ensure-python3.sh — pre-resolved(add to PATH: simpler, doesn't change production code)
- spc-187 sed scope: all files vs. only comments/prose — pre-resolved(all files: the string should be spc-186 everywhere)

## Decision journal

## Pending decisions

## Attempts

## Notes

## References

- Review artifact: [Lattice Batch Review](https://claude.ai/code/artifact/bb313d94-c7ac-4b3d-967b-e5dcdfa7e649)
- ADR-007: hard-limit scope law
- spc-186: hard-limit-closure (parent workstream)
- spc-212: python3-friendly-guard
