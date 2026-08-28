# tkt-149-ratify-transaction

> **TL;DR:** Restore the human-owned parked-to-queued transition with a portable, contained, commit-safe ratification writer.
> **Kind:** bug · **Priority:** P1
> **Path:** rev-20260828-082751Z → tkt-149 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/149 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | Make ratification executable, portable, atomic-at-file level, and commit-safe |
| spec | (none — ticket-only) |
| covers | A1, A2, A3, A4 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/ratify.sh; skills/_lattice-lib/scripts/tests/ratify.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-149 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-149-ratify-transaction` |
| worktree | sibling `…/lattice.worktrees/tkt-149-ratify-transaction/` |
| prs | (none) |

## Acceptance

- [ ] **A1** A canonical parked binder ratifies successfully, records one dated decision, settles the selected pending decision, flips to `queued`, and creates one commit containing only that binder.
- [ ] **A2** Non-parked, missing-journal, untracked/out-of-home, symlinked, malformed, and unrelated-staged preconditions fail before mutation.
- [ ] **A3** Decision journal at EOF and before another section both work; rerun is fail-safe and does not duplicate the ratification.
- [ ] **A4** GNU/Linux and macOS-compatible Bats plus full `bash tools/ci-local.sh` pass.

## Approach

- Replace the shell/sed read-modify-write with a small Python-backed transaction inside the trusted script.
- Resolve and contain the binder under the current repo's `.lattice/tickets/`; reject symlink components and untracked files.
- Lock the binder directory, re-read status under lock, update the journal/pending section/status in memory, then fsync + atomic replace.
- Define how the selected pending decision is identified; keep the interface explicit and deterministic.
- Check the Git index before mutation and refuse unrelated staged paths; stage and commit only the binder.
- Add a dedicated Bats suite covering success, malformed inputs, EOF layout, idempotency/fail-safe behavior, containment, and staged-file isolation.

## Anticipated decisions

- Ratification writer implementation language — disposition: pre-resolved (existing trusted helpers): Python stdlib embedded from Bash.
- Pending-decision selection — disposition: agent-decides; choose the smallest explicit CLI surface and document it in help/tests.
- Unrelated staged files — disposition: pre-resolved (ticket Acceptance): fail before mutation rather than implicitly preserving/committing them.

## Decision journal

## Pending decisions

## Attempts

## Notes

## References

- Review: `rev-20260828-082751Z`
- GitHub issue body is SoT for long prose

## Lineage

- Parent spec: none
- Parent issue: none
- Primary ticket: **tkt-149**
- Related tickets: none
- Covers: **A1, A2, A3, A4**
- Blocked by: none
- Parallel group: G1
- Worktree bind: `tkt-149-ratify-transaction`

## Finish

- (none yet)
