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
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-29T16:30:00Z |
| updated | 2026-08-29T17:12:19Z |
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

- [x] **A1** `reconcile-state.bats` "gh not installed" test passes (exit 2)
- [x] **A2** `close-fixed-issues.bats` "missing extractor lib" test passes (exit 2)
- [x] **A3** `.batch-work-active` not tracked (git rm --cached; gitignore reverted per check-pr-context.sh invariant)
- [x] **A4** `queue_health.py` banner has no spurious separator
- [x] **A5** `ci-gate-check.sh` binder write uses `fcntl.flock`
- [x] **A6** `grep -rn spc-187` returns zero hits across codebase (reviews excluded — historical)
- [x] **A7** `arr_json()` escapes both backslash and double-quote
- [x] **A8** Full bats test suite passes (973/976; 1 pre-existing failure unchanged)

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

- 2026-08-29 — batch-merge-gate escape authorized (spc-186 A1, ADR-007 §5b). rule_id=batch-merge-gate; reason="user-authorized: stale tracked artifact from git rm --cached, not an active batch — this PR removes it"; authorizer=operator; marker_removed=true; ts=2026-08-29T17:10:00Z
- 2026-08-29 — .gitignore revert: check-pr-context.sh invariant (line 36-39) requires .batch-work-active to stay untracked-dirty, not gitignored; code-review finding confirmed (source: code-review)
- 2026-08-29 — reconcile-state.bats PATH approach: shadow-dir with gh removed replaces fragile whitelist; code-review finding addressed (source: code-review)

## Pending decisions

## Attempts

## Notes

## References

- Review artifact: [Lattice Batch Review](https://claude.ai/code/artifact/bb313d94-c7ac-4b3d-967b-e5dcdfa7e649)
- ADR-007: hard-limit scope law
- spc-186: hard-limit-closure (parent workstream)
- spc-212: python3-friendly-guard

## Finish

- pr-217 merged: 2026-08-29T17:11:14Z — https://github.com/percena/lattice/pull/217 (base merge)
- issue #216 closed: 2026-08-29T17:11:37Z — https://github.com/percena/lattice/issues/216
