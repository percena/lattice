# tkt-163-review-path-robustness

> **TL;DR:** Make review-context head snapshots race-free (no shared FETCH_HEAD window) and stamp-pr-open comment dedup fail-closed on transient gh errors.
> **Kind:** bug · **Priority:** P2
> **Path:** repo-review 2026-08-28 → tkt-163 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/163 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | FETCH_HEAD TOCTOU → per-run ref; dedup gh-failure → skip posting with loud warning |
| spec | (none — ticket-only) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/build-review-context.sh; skills/_lattice-lib/scripts/stamp-pr-open.sh; skills/_lattice-lib/scripts/tests/ |
| solo_merge | yes |
| **primary_ticket** | tkt-163 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-163-review-path-robustness` |
| worktree | sibling `…/lattice.worktrees/tkt-163-review-path-robustness/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** Head snapshot no longer races through shared `FETCH_HEAD`; a concurrent fetch cannot yield a mislabeled `head:pr-N` manifest entry.
- [ ] **A2** When the dedup read fails, no comment is posted (warning printed, clearly-marked outcome); a successful re-run posts exactly one comment.
- [ ] **A3** Bats coverage: ref-isolation (or concurrent-fetch simulation) for A1; gh-failure path for A2.

## Notes

- `FETCH_HEAD` lives in the common git dir shared by all worktrees — batch-work parallel agents can interleave between the fetch and the `git show` (`build-review-context.sh:343-344`).
- `stamp-pr-open.sh:429-431` `|| true` + `-n` guard skips dedup on transient failure → duplicate comments; also `--json comments` returns only ~100 latest (old markers fall out of window).
- Mirror the library's existing correct concurrency pattern (`finish-ledger.sh` flock).
- Path-disjoint from in-flight tkt-149 (ratify.sh) and tkt-150 (finish-ledger.sh).

## References

- `finish-ledger.sh` — flock + atomic-write pattern to mirror

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-163**
- Covers: A1, A2, A3
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-163-review-path-robustness`

## Finish

- (none yet)
