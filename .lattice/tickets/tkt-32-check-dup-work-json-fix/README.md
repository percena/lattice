# tkt-32-check-dup-work-json-fix

> **TL;DR:** Fix JSON injection (--json output) + worktree token double-counting in check-duplicate-work.sh
> **Kind:** fix · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/32 |
| status | closed |
| adopted | false |
| summary | fix check-duplicate-work.sh JSON escaping + worktree double-counting |
| spec | (none — review-fix) |
| covers | A1, A2 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/_lattice-lib/scripts/check-duplicate-work.sh |
| solo_merge | no (rides with tkt-31) |
| **primary_ticket** | tkt-31 |
| **related_tickets** | tkt-31, tkt-33, tkt-34 |
| **worktree_bind** | tkt-31-run-e2e-symlink-fix (shared) |
| prs | pr-36 — https://github.com/percena/lattice/pull/36 |

## Acceptance (this slice)

- [x] **A1** `--json` output is valid JSON for issue/PR titles containing double-quotes, backslashes, and newlines (built via `jq -nc --arg`, not hand-concatenation)
- [x] **A2** Worktree surface does not double-count the same title token (path-substring + branch-token); each title token counted at most once per worktree

## Notes

- Source: review-code pass on dev→main change set (2026-08-25)
- Lines 167, 200, 226 — hand-concatenated JSON objects
- Lines 190-196 — `SHARED=$((SHARED + PATH_SHARED))` double-counts

## References

- GitHub issue body is SoT for long prose

## Finish

- pr-36 merged: 2026-08-25T09:45:49Z — https://github.com/percena/lattice/pull/36 (base merge)
- issue #32 closed: 2026-08-25T09:46:37Z — https://github.com/percena/lattice/issues/32
