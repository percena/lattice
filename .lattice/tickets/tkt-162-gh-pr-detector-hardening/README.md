# tkt-162-gh-pr-detector-hardening

> **TL;DR:** Fix gh-pr detector strict-mode false positives (arg-list collisions), document or close the nested-shell bypass, and give the detector its own bats suite.
> **Kind:** bug · **Priority:** P2
> **Path:** repo-review 2026-08-28 → tkt-162 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/162 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | detector strict-mode FP fix + bash -c/eval bypass decision + dedicated bats |
| spec | (none — ticket-only) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | plugins/lattice/scripts/detect-gh-pr-command.py; plugins/lattice/scripts/tests/detect-gh-pr-command.bats (new); plugins/lattice/hooks/lib/intercept-gh-pr-common.sh (comments) |
| solo_merge | yes |
| **primary_ticket** | tkt-162 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-162-gh-pr-detector-hardening` |
| worktree | sibling `…/lattice.worktrees/tkt-162-gh-pr-detector-hardening/` |
| prs | pr-169 — https://github.com/percena/lattice/pull/169 |

## Acceptance (this slice)

- [x] **A1** Arg-list false positives fixed (non-gh first token / end-of-options awareness or equivalent); regression tests for `touch gh pr create`, `mv gh pr create`, `git checkout -- gh pr create`, `find . -name gh -o -name pr -o -name create`.
- [x] **A2** Nested-shell bypass (`bash -c` / `sh -c` / `eval`) either detected or documented as accepted limitation (code + docs), with tests pinning the chosen behavior.
- [x] **A3** Dedicated `detect-gh-pr-command.bats` covers VALUE_FLAGS missing-value, TERMINAL_FLAGS before verb, wrapper `--` handling, `sudo -u gh pr create` allow-path.

## Notes

- Reproduced on dev @ dcc27b4 (post-#154): `touch gh pr create` → exit 0 (would block in strict); `bash -c 'gh pr create'` → exit 1 (undetected).
- Fail-open contract and advisory default stay unchanged.

## References

- #154 / ADR-006 — adjacent PreToolUse stack (shipped with tests; not in scope)
- `strip-quoted-and-heredocs.py:32-35` — the existing accepted-limitation pattern to mirror

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-162**
- Covers: A1, A2, A3
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-162-gh-pr-detector-hardening`

## Finish


- pr-169 merged: 2026-08-28T11:04:10Z — https://github.com/percena/lattice/pull/169 (base merge)
- issue #162 closed: 2026-08-28T11:04:15Z — https://github.com/percena/lattice/issues/162
