# tkt-356-a4-partial-line-macos-portability

> **TL;DR:** A4 status-row guard partial-line simulation breaks on macOS (BSD sed/grep); bats test 7/11 red locally, green in CI.
> **Kind:** bug · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug,P2 |
| github | https://github.com/percena/lattice/issues/356 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T05:19:22Z |
| updated | 2026-09-02T05:51:50Z |
| adopted | false |
| summary | A4 partial-line status-row simulation breaks on macOS (BSD sed/grep); test 7/11 red locally, green in CI. |
| spec | spc-337 — FSM conformance closure (path: ../../specs/spc-337-fsm-conformance-closure.md) |
| covers | A4 follow-up (env-portability) |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | plugins/lattice/hooks/intercept-shippable-write.sh, plugins/lattice/scripts/tests/intercept-shippable-write-status-row.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-356 (this issue) |
| worktree_bind | tkt-357-done-flip (binder creation pass; implementation gets its own tree) |
| prs | pr-359 — https://github.com/percena/lattice/pull/359 |

## Acceptance (this slice)

- [x] test 7 passes on macOS — deny partial-line status change with correct message.
- [x] test 11 passes on macOS — allow partial-line edit leaving status value intact.
- [x] `bats plugins/lattice/scripts/tests/intercept-shippable-write-status-row.bats` all-green on macOS darwin.
- [x] CI stays green (no regression on Linux).

## Approach

1. Read `intercept-shippable-write.sh` partial-line simulation path (the section that simulates the Edit on disk and compares status values).
2. Replace BSD/GNU-dependent sed/grep line manipulation with env-independent string ops (portable Python — the hook already shells out to helpers, or POSIX-only string ops).
3. Verify test 7 + 11 pass on both macOS and Linux; full suite stays green.

Touch-set: `plugins/lattice/hooks/intercept-shippable-write.sh`, `plugins/lattice/scripts/tests/intercept-shippable-write-status-row.bats` (if test assertions need updating for new message format).

## Anticipated decisions

- Simulation implementation language — pre-resolved (ADR-012 §1: stamps/path-point scripts; the hook is a Bash script that may call Python helpers, matching the existing `intercept-shippable-write.sh` style which already uses `jq` + Python snippets).

## Decision journal

## Notes

- NOTICED: .lattice/.transition-ledger/tkt-357.jsonl — finish-ledger.sh stamped binder closed but did not append pr-open→closed ledger entry (transition_ledger_snapshot_mismatch); recorded the missing transition to unblock CI (out-of-paths, 2026-09-02)

- Filed as a post-spc-337 soak follow-up; surfaced by the dogfood cycle on 2026-09-02 (CI green on dev, local red on macOS darwin).
- Root-cause class: same as #353 (host-environment-dependent bats), different root cause (BSD vs GNU sed/grep in partial-line simulation).

## Lineage

- Parent spec: **spc-337**
- Parent issue (GH sub-issue of Spec primary #337): **#337**
- Primary ticket: **tkt-356**
- Refs: #353 (same env-portability class), ADR-012 §1
- Covers: **A4 follow-up (env-portability)**
- Worktree bind: tkt-357-done-flip (binder creation pass)
- Child PRs: (none yet)

## Assets

## Finish


- pr-359 merged: 2026-09-02T05:50:44Z — https://github.com/percena/lattice/pull/359 (base merge)
- issue #356 closed: 2026-09-02T05:51:02Z — https://github.com/percena/lattice/issues/356
