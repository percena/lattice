# tkt-298 — Migrate batch-work coordinator from record to commit

> **TL;DR:** The coordinator flipped status via `record` (ledger-only, no binder flip) → A1.5's snapshot/continuity checks flag it. Route the stuck flip through `commit`; drop the duplicate ok flip (stamp-pr-open owns it).
> **Kind:** bug · **Path:** tkt-271 (pr-296 review) → tkt-298 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug |
| github | https://github.com/percena/lattice/issues/298 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-01T10:50:00Z |
| updated | 2026-09-01T07:50:50Z |
| adopted | true |
| summary | Coordinator flips stuck via commit (binder+ledger atomic); drops the duplicate ok flip (stamp-pr-open owns it). |
| spec | (none — follow-up) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/batch-work/scripts/lib/coordinator.py, skills/batch-work/scripts/tests/coordinator.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-298 (this issue) |
| **related_tickets** | tkt-271 (surfaced) |
| **worktree_bind** | `tkt-298-coordinator-commit-migration` |
| prs | pr-305 — https://github.com/percena/lattice/pull/305 |

## Acceptance (this slice)

- [x] coordinator.py flips the binder via `commit` (not `record`) for unknown/timeout (in-progress→stuck + --wait-reason unblock), so the binder and ledger agree atomically.
- [x] Exactly one ledger entry per real flip — the ok flip is NOT recorded by the coordinator (the worker's create-pr/stamp-pr-open owns it; single source of truth, no discontinuity).
- [x] The validator's snapshot/continuity checks pass on coordinator-produced ledgers (stuck test: binder flipped to stuck, ledger final to=stuck).
- [x] batch-work bats + transition-api green (coordinator 10/11 + run-process-wave 10/10 + spawn-ticket-process 4/5; the 2 failures are env-only — `claude` CLI on the local PATH, absent in CI; transition-api 26/26).

## Approach

The worker (spawned agent) stops at `create-pr` → `stamp-pr-open` already flipped in-progress→pr-open via `commit` (post-tkt-271). So the coordinator's ok-record was a duplicate (a discontinuity under A1.5). Drop it. For unknown/timeout (worker crashed/timed out, no PR, binder still in-progress), the coordinator is the sole recorder → it flips the binder to stuck via `commit` (in-progress→stuck + wait_reason: unblock). Best-effort: a missing binder (worker crashed before start-work) warns + continues (DAG state is the SoT).

## Decision journal

- 2026-09-01 — ok flip dropped (stamp-pr-open owns it; the worker stops at create-pr so the binder is already pr-open when the coordinator settles an ok node). unknown/timeout → commit (sole recorder for crashed workers). Reversible+local.
- 2026-09-01T07:49:36Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #305) [WARN — signal logged, not silently lost]

## Lineage

- Surfaced by: tkt-271 (pr-296 review)
- GitHub: #298

## Finish


- pr-305 merged: 2026-09-01T07:50:02Z — https://github.com/percena/lattice/pull/305 (base merge)
- issue #298 closed: 2026-09-01T07:50:23Z (reason: completed) — https://github.com/percena/lattice/issues/298
