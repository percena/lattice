# tkt-361-spawn-zombie-fix

> **TL;DR:** spawn-ticket-process.bats 'missing claude binary' fails on root — `kill -0` sees zombie as alive
> **Kind:** bug · **Priority:** P3
> **Path:** none → tkt-361 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P3 |
| labels | bug, P3 |
| github | https://github.com/percena/lattice/issues/361 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T00:00:00Z |
| updated | 2026-09-02T09:24:49Z |
| adopted | true |
| summary | Fix is_alive() zombie detection + test outcome-based assertion |
| spec | none (post-spc-337 leftover audit) |
| covers | A1, A2 |
| paths | skills/batch-work/scripts/tests/spawn-ticket-process.bats, skills/batch-work/scripts/spawn-ticket-process.sh |
| **primary_ticket** | tkt-361 (this issue) |
| **related_tickets** | tkt-362, tkt-363 (same batch PR) |
| **worktree_bind** | tkt-361-spc337-leftover-audit |
| worktree | sibling lattice.worktrees/tkt-361-spc337-leftover-audit/ |
| prs | pr-380 — https://github.com/percena/lattice/pull/380 |

## Acceptance (this slice)

- [x] **A1** The test is green as root and non-root: assert on the documented outcome (dead PID / 'did not produce a live process') rather than a specific exit code, or make the script's exit code for a dead spawn deterministic (document it in the usage header).
- [x] **A2** `bats skills/batch-work/scripts/tests/` fully green on the dogfood host.

## Approach

`is_alive()` now checks `ps -p <pid> -o state=` for zombie (`Z`) after `kill -0` passes — a disowned spawn that immediately fails exec becomes a zombie that `kill -0` sees as alive on Linux root. The test asserts `[ "$status" -ne 0 ]` (any failure) + the failure message, rather than exactly exit 1.

## Decision journal

- Zombie detection via `ps -o state=` → implemented (source: agent-judgment)

## Notes

- Batch PR with tkt-362 (docs residue) and tkt-363 (slug-named ledger replay).

## References

- GitHub issue body is SoT for long prose
- Worktree policy: one tree ↔ one PR; spc|tkt open binds

## Finish

- pr-380 merged: 2026-09-02T09:23:43Z — https://github.com/percena/lattice/pull/380 (base merge)
- issue #361 closed: 2026-09-02T09:24:08Z (reason: completed) — https://github.com/percena/lattice/issues/361
