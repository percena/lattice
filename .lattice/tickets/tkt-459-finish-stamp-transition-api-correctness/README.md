# tkt-459-finish-stamp-transition-api-correctness

> **TL;DR:** Correctness fixes on the post-merge stamp path and the transition chokepoint (ADR-013 class).
> **Kind:** fix · **Priority:** P1
> **Path:** spc-458 → tkt-459 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/459 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-03T16:51:19Z |
| adopted | false |
| summary | Fix pr-N substring discovery, ledger-before-rename ordering, transition-api guards, finish-commit untracked, CI validator step |
| spec | spc-458 — Review follow-up (path: ../../specs/spc-458-review-followup.md) |
| covers | A1, A2, A3, A4 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/scripts/{finish-stamp-ci.py,finish-stamp.py,transition-api.py,finish-commit.sh}, skills/_lattice-lib/scripts/tests/**, .github/workflows/finish-stamp.yml |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-459 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-459-finish-stamp-transition-api-correctness` |
| worktree | sibling `…/lattice.worktrees/tkt-459-finish-stamp-transition-api-correctness/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** `finish-stamp-ci.py` discovers binders by `\bpr-N\b` (pr-44 ≠ pr-440, bats-proven); push/fetch failure exits non-zero; commit uses the staged set, not `-- .lattice/`.
- [ ] **A2** `finish-stamp.py` appends the ledger edge before the binder rename and removes it on rename failure; `finish-stamp.bats` + `finish-ledger.bats` green.
- [ ] **A3** `transition-api.py commit` arity guard → usage + exit 3; `_rollback_ledger` finds the entry anywhere and warns when absent; temp file `.transition-api.*.tmp` unlinked on failure; `transition-api.bats` green.
- [ ] **A4** `finish-commit.sh` uses `--untracked-files=no`; `finish-stamp.yml` runs the artifact validator before push.

## Approach

1. `finish-stamp-ci.py`: `re.search(rf"\bpr-{pr_num}\b", …)`; `commit_and_push` returns 1 on fetch failure and on retry-push failure; `git commit -m` without pathspec (staged set); add `tests/finish-stamp-ci.bats` (fixture tickets dir with pr-44 and pr-440 binders; `discover_binders` via `python3 -c`; return codes via a fake `git` on PATH).
2. `finish-stamp.py`: move the `record` subprocess before `os.replace`; on rename failure call `transition-api.py` rollback path (or truncate the just-appended line under the same lock helper); keep idempotent no-op branch intact.
3. `transition-api.py`: `if len(args) < 4: usage; return 3`; `_rollback_ledger` → find last index of needle, rewrite without it, else stderr WARNING; `tmp = binder.parent / f".transition-api.{pid}.tmp"` + unlink in except.
4. `finish-commit.sh:79`: add `--untracked-files=no`.
5. `finish-stamp.yml`: step `python3 tools/validate-lattice-artifacts.py` between stamp and push (fail → no push).
Touch-set: see `paths` row.

## Anticipated decisions

- Rename-failure rollback in finish-stamp.py: reuse `transition-api.py` private `_rollback_ledger` vs local truncate — disposition: agent-decides (reversible, ticket-local; prefer importing the module function to avoid a 3rd copy).
- Return code for finish-stamp-ci push failure (1 vs 2) — disposition: pre-resolved(spc-458 A1): non-zero; 1.

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

- (none)

## Attempts

- (none)

## Notes

- `stamp-pr-open.sh` `|| true` ledger staging is a sibling defect but the file is touched by open PR #453 — NOTICED, not folded in.

## References

- Spec: `spc-458` · ADR-013 · ADR-012 · `binder_rows.merge_row` (canonical `\bpr-N\b`)

## Lineage

- Parent spec: **spc-458**
- Parent issue: **#458**
- Primary ticket: **tkt-459**
- Covers: **A1, A2, A3, A4**
- Blocked by: none
- Parallel group: (serial)
- Worktree bind: `tkt-459-finish-stamp-transition-api-correctness`

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
