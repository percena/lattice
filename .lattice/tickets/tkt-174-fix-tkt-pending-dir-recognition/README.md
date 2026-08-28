# tkt-174-fix-tkt-pending-dir-recognition

> **TL;DR:** Validator rejects tkt-pending-* dirs that its own warnings recommend — contradiction
> **Kind:** bug · **Priority:** P1
> **Path:** (ticket-only) → tkt-174 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/174 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | tkt-pending-* dirs rejected by malformed_ticket_id but recommended by phantom_binder_smell warning |
| spec | (none — ticket-only) |
| covers | A1, A2, A3, A4 |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-174 (this issue) |
| **related_tickets** | tkt-155 (original PR #173) |
| **worktree_bind** | `tkt-174-fix-tkt-pending-dir-recognition` |
| worktree | sibling `…/lattice.worktrees/tkt-174-fix-tkt-pending-dir-recognition/` |
| prs | (none) |

## Acceptance (this slice)

- [x] **A1** `tkt-pending-<slug>` dirs are recognized as a valid transient state — `malformed_ticket_id` does NOT fire on them.
- [x] **A2** `binder_github_pending` fires as a standalone warning (no error) on `tkt-pending-*` dirs with placeholder github.
- [x] **A3** A bats test covers the `binder_github_pending` code path with a `tkt-pending-*` dir.
- [x] **A4** Full `bash tools/ci-local.sh` passes.

## Approach

Add `TKT_PENDING_DIR_RE` regex to recognize `tkt-pending-<slug>` dir names. Exempt them from `malformed_ticket_id` so `binder_github_pending` can fire cleanly as a standalone warning (A3 posture from tkt-155).

## References

- GitHub issue: https://github.com/percena/lattice/issues/174
- PR #173 (tkt-155 original fix — introduced the contradiction)
- Code-review findings (6 findings, 3 high-severity tkt-pending contradiction cluster)
