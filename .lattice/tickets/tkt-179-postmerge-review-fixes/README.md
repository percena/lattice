# tkt-179-postmerge-review-fixes

> **TL;DR:** Fix 9 verified MEDIUM findings from the post-merge review of tkt-149..152.
> **Kind:** bug · **Priority:** P1
> **Path:** rev-20260828-082751Z → tkt-179 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/179 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | true |
| summary | Fix 9 confirmed MEDIUM findings across ratify, finish-ledger, validator, reconcile-state |
| spec | (none — ticket-only) |
| covers | A1, A2, A3, A4, A5, A6, A7, A8, A9, A10 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/_lattice-lib/scripts/ratify.sh; skills/_lattice-lib/scripts/tests/ratify.bats; skills/_lattice-lib/scripts/finish-ledger.sh; skills/_lattice-lib/scripts/tests/finish-ledger.bats; tools/validate-lattice-artifacts.py; tools/tests/lattice-artifacts.bats; skills/_lattice-lib/scripts/reconcile-state.sh; skills/_lattice-lib/scripts/tests/reconcile-state.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-179 |
| **related_tickets** | tkt-149, tkt-150, tkt-151, tkt-152 |
| **worktree_bind** | `tkt-179-postmerge-review-fixes` |
| worktree | sibling `…/lattice.worktrees/tkt-179-postmerge-review-fixes/` |
| prs | pr-180 |

## Acceptance

- [x] **A1** ratify M1: document recovery recipe (`git checkout -- <binder>`) in script header OR implement rollback-to-original on commit failure
- [x] **A2** ratify M2: reject multi-line `--decision` at the Bash arg-parsing layer
- [x] **A3** finish-ledger M1: validate `--closed-at` against ISO-8601 in the cancel path (outside the `ISSUE_M` conditional)
- [x] **A4** finish-ledger M2 + validator: add `FINISH_CANCELLED_RE` to `finish_ledgr_terminal()` so `- cancelled:` lines are recognized as terminal evidence
- [x] **A5** validator M1: change `concluded_review_no_outcome` condition to `not rv_out` only (let `invalid_review_outcome` handle invalid non-null values)
- [x] **A6** validator M2: change `spec_status` to use `parse_front_matter` instead of full-text `re.search`
- [x] **A7** reconcile-state M1: add `open_issue_closed_binder` drift class (issue OPEN + binder `closed`)
- [x] **A8** reconcile-state M2: add drift check for MERGED PR + terminal binder + no Finish ledger (`merged_pr_missing_finish_ledger`)
- [x] **A9** reconcile-state M3: when `--repo` is passed and `binder_repo_id` is None, require github URL identity or emit identity-unverified warning
- [x] **A10** Full `bash tools/ci-local.sh` passes with updated/expanded tests

## Approach

- All 9 findings are independently verified TRUE by reading code and tracing execution paths.
- Fixes are mostly small (1-5 lines each) with corresponding test additions.
- ratify M1: prefer documenting recovery recipe (rollback is complex and the script header already acknowledges the design tradeoff per ADR-004).
- finish-ledger M1: move CLOSED_AT ISO validation outside the ISSUE_M conditional.
- finish-ledger M2 + validator M1 + M2: all in validate-lattice-artifacts.py — add cancel regex, fix double-finding condition, switch spec_status to parse_front_matter.
- reconcile-state M1+M2+M3: add drift classes and identity fallback in the embedded Python.

## Decision journal

- ratify M1 rollback: pre-resolved — document recovery recipe, not full rollback (ADR-004 design tradeoff)

## Pending decisions

## Attempts

## Notes

## References

- Review: `rev-20260828-082751Z`
- Source PRs: #156 (tkt-150), #157 (tkt-151), #158 (tkt-149), #165 (tkt-152)
- Verification agents confirmed all 9 findings TRUE

## Lineage

- Parent spec: none
- Parent issue: none
- Primary ticket: **tkt-179**
- Related tickets: tkt-149, tkt-150, tkt-151, tkt-152
- Covers: **A1, A2, A3, A4, A5, A6, A7, A8, A9, A10**
- Blocked by: none
- Parallel group: none
- Worktree bind: `tkt-179-postmerge-review-fixes`

## Finish


- pr-180 merged: 2026-08-28T14:23:52Z — https://github.com/percena/lattice/pull/180 (base merge)
- issue #179 closed: 2026-08-28T14:24:01Z — https://github.com/percena/lattice/issues/179
