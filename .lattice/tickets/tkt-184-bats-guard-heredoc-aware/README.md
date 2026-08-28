# tkt-184-bats-guard-heredoc-aware

> **TL;DR:** The tkt-167 assertion guard flagged heredoc-embedded fixtures as violations (self-flagging its own test file on dev); make the checker heredoc-aware.
> **Kind:** bug · **Priority:** P1
> **Path:** tkt-167 follow-up → tkt-184 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/184 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | check-bats-assertions skips heredoc bodies; regression test pins the behavior |
| spec | (none — ticket-only) |
| covers | A1, A2 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | tools/check-bats-assertions.py; tools/tests/bats-assertion-ergonomics.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-184 |
| **related_tickets** | tkt-167 |
| **worktree_bind** | `tkt-184-bats-guard-heredoc-aware` |
| worktree | sibling `…/lattice.worktrees/tkt-184-bats-guard-heredoc-aware/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** Checker skips heredoc bodies (`<<TAG` / `<<-TAG`, quoted or unquoted delimiters).
- [ ] **A2** Regression test: heredoc-embedded banned forms are NOT flagged; a real banned line still is. ci-local green on dev.

## Notes

- Root cause of the dev-HEAD failure: in the tkt-167 worktree the guard file was untracked when the corpus scan ran (`git ls-files` omitted it), so the self-flag surfaced only after merge — a scan-scope gap in that ticket's verification.
- Reproduced pre-fix: `bats tools/tests/bats-assertion-ergonomics.bats` → tests 3+4 fail on the old checker, pass on the fixed one.

## Lineage

- Parent issue: none (ticket-only)
- Follow-up of: tkt-167

## Finish

- (none yet)
