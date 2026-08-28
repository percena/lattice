# tkt-175-postmerge-review-followups

> **TL;DR:** Fix the `git bisect run gh pr create` detector bypass introduced by tkt-162, and harden the batch's own tests (assertion ergonomics + fragility).
> **Kind:** bug · **Priority:** P1
> **Path:** post-merge review of tkt-159..163 → tkt-175 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/175 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | git bisect-run exec-trigger + ci-local.bats assertion hardening + small fail-closed/forced-refspec follow-ups |
| spec | (none — ticket-only) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | plugins/lattice/scripts/detect-gh-pr-command.py; plugins/lattice/scripts/tests/detect-gh-pr-command.bats; tools/tests/ci-local.bats; tools/tests/validators-hardening.bats; skills/_lattice-lib/scripts/stamp-pr-open.sh; skills/_lattice-lib/scripts/build-review-context.sh |
| solo_merge | yes |
| **primary_ticket** | tkt-175 |
| **related_tickets** | tkt-162, tkt-163, tkt-160, tkt-159 |
| **worktree_bind** | `tkt-175-postmerge-review-followups` |
| worktree | sibling `…/lattice.worktrees/tkt-175-postmerge-review-followups/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** `git bisect run gh pr create` (create + merge verbs) detected again; `git checkout -- gh pr create` and `git bisect start gh pr create` remain safe; full plugin suite green.
- [ ] **A2** `tools/tests/ci-local.bats` free of non-terminal `[[ ]]`/`! cmd` assertions; the valid-ref test no longer asserts whole-run exit 0.
- [ ] **A3** Denylist covers `from tomllib|from zoneinfo`; stamp-pr-open dedup fail-closed on any eval exception; build-review-context fetch uses a forced (`+`) refspec; new/changed tests verified to fail pre-fix.

## Notes

- Repro for A1 (verified on dev @ d7e11c5): `printf '%s' 'git bisect run gh pr create' | python3 plugins/lattice/scripts/detect-gh-pr-command.py create` → exit 1 (allowed) post-tkt-162, was exit 0 (blocked) before.
- The full-corpus assertion sweep stays with #167; A2 covers only this batch's own file.
- `expect_safe` should also assert empty stdout so a detector crash (exit 1 + traceback) can't masquerade as "safe".

## References

- tkt-162 (introduced the regression), #167 (systemic assertion sweep), tkt-163 (test-ergonomics discovery)

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-175**
- Covers: A1, A2, A3
- Blocked by: (none)
- Parallel group: G1

## Finish

- (none yet)
