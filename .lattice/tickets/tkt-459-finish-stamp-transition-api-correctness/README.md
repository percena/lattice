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
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-03T17:19:39Z |
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
| prs | pr-465 — https://github.com/percena/lattice/pull/465 |

## Acceptance (this slice)

- [x] **A1** `finish-stamp-ci.py` discovers binders by `\bpr-N\b` (pr-44 ≠ pr-440, bats-proven); push/fetch failure exits non-zero; commit uses the staged set, not `-- .lattice/`.
- [x] **A2** `finish-stamp.py` appends the ledger edge before the binder rename and removes it on rename failure; `finish-stamp.bats` + `finish-ledger.bats` green.
- [x] **A3** `transition-api.py commit` arity guard → usage + exit 3; `_rollback_ledger` finds the entry anywhere and warns when absent; temp file `.transition-api.*.tmp` unlinked on failure; `transition-api.bats` green.
- [x] **A4** `finish-commit.sh` uses `--untracked-files=no`; `finish-stamp.yml` runs the artifact validator before push.

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
- 2026-09-03 rename-failure rollback in finish-stamp.py → extracted `build_entry()` in transition-api.py and call `_append_ledger_locked` / `_rollback_ledger` in-process instead of the `record` subprocess (source: agent-judgment, reversible, ticket-local; avoids a third copy of the entry builder — chain source: `transition-api.py cmd_record`).
- 2026-09-03 finish-stamp-ci push/fetch failure exit code → 1 (source: pre-resolved spc-458 A1).
- 2026-09-03 validator-before-push → implemented as `--validator-script/--validator-baseline` flags on finish-stamp-ci.py rather than a separate workflow step, so the push is guarded in the same process that made the commit and consumer repos can pass their own validator (source: agent-judgment, reversible).
- 2026-09-03 `finish-commit.bats` "stranded unstaged" fixture planted an UNTRACKED file; re-modelled as a tracked-modified binder (the real tkt-360 symptom) so the test still guards the class after `--untracked-files=no` (source: agent-judgment).

## Pending decisions

- (none)

## Attempts

- attempt 1 · 2026-09-03 · direct fix per Approach · suites: finish-stamp-ci 6/6, finish-stamp 9/9, finish-commit 7/7, finish-ledger 58/58, transition-api 42/42, stamp-pr-open 27/27, ensure-workspace-stamp 10/10, transition-parity 8/8 (local bats 1.2.1, root) · ci-local full run pending

## Notes

- `stamp-pr-open.sh` `|| true` ledger staging is a sibling defect; #453 has since merged — NOTICED for a follow-up ticket, not folded in.
- NOTICED-drain (dev red, out-of-paths, 2026-09-03): `.lattice/specs/spc-441-hardening-sweep.md` was flipped `locked → done` by direct commit 17d5663 with A1–A8 unchecked + a stale TL;DR header → `artifacts.yml` red on dev (`spec_done_open_acceptance`, `spec_header_status_mismatch`) — the same class as spc-433/#440. Drained here: boxes checked (all 8 PRs merged, tkt-442..449 closed in 0572c63), header fixed. Recurrence #2 of "locked→done flip has no scripted chokepoint".
- NOTICED-drain (dev red, out-of-paths, 2026-09-03): `plugins/lattice/hooks/lib/status-row-guard.sh` (extracted by #456) references caller-set variables → `lint.yml` shellcheck `-S warning` SC2154 red on dev. Drained here with a file-level `# shellcheck disable=SC2154` + justification (sourced library contract).

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
