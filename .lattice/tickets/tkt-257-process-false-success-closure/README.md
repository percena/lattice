# tkt-257-process-false-success-closure

> **TL;DR:** Redefine process-node final state ok|failed|timeout|unknown; unknown fail-closes binder to stuck
> **Kind:** feat · **Status:** closed · **Priority:** P1
> **Path:** spc-254 → tkt-257 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/257 |
| status | closed |
| adopted | false |
| summary | Redefine process-node final state ok|failed|timeout|unknown; unknown fail-closes binder to stuck |
| spec | spc-254 — Executable workflow contracts (path: ../../specs/spc-254-executable-workflow-contracts.md) |
| covers | A1 |
| blocked_by | #256 |
| parallel_group | l2-batch |
| paths | skills/batch-work/scripts/run-process-wave.sh, skills/batch-work/scripts/tests/ |
| solo_merge | yes |
| primary_ticket | tkt-257 |
| related_tickets | (none) |
| worktree_bind | tkt-257-process-false-success-closure |
| prs | pr-268 — https://github.com/percena/lattice/pull/268 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T04:50:00Z |

## Acceptance (this slice)

- [x] **A1**
- mirror spc-254 A* criteria for this slice; see Spec for full text.
  - Implemented in `skills/batch-work/scripts/run-process-wave.sh`: process-node
    final state redefined from exit/result artifact (`$BATCH_RESULT_FILE`) +
    `claude agents --json` + PID liveness + `verify-mutation --expected-oid`,
    classified `ok|failed|timeout|unknown`; `unknown` fail-closes the binder to
    `stuck + wait_reason: unblock` via `transition-api.py record`. A PID that
    disappeared is never named success; `ok` requires agreement across the
    available signals. Fault-injection evidence in
    `skills/batch-work/scripts/tests/run-process-wave.bats` (5 A1 cases).

## Notes

- Foundation/parallel per ship plan: layer 0=(tkt-255) serial; layer 1=tkt-256/260/261; layer 2=tkt-257(after 256)/tkt-259(after 255); layer 3=tkt-258(after 255+257).
- One sibling worktree per concurrent ship slot.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/257
- Spec: `spc-254` (path above)
- Review: `rev-20260830-141357Z`

## Lineage

- Parent spec: **spc-254**
- Parent issue: **#254** (sub-issue of Spec primary)
- Primary ticket: **tkt-257**
- Covers: **A1**
- Blocked by: #256
- Parallel group: l2-batch
- Worktree bind: tkt-257-process-false-success-closure
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish


- pr-268 merged: 2026-08-31T04:55:01Z — https://github.com/percena/lattice/pull/268 (base merge)
- issue #257 closed: 2026-08-31T04:55:20Z — https://github.com/percena/lattice/issues/257
