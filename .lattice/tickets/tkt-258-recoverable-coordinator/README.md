# tkt-258-recoverable-coordinator

> **TL;DR:** Coordinator persists DAG/layer/node/attempt/cursor; no model inference; resume after restart
> **Kind:** feat · **Status:** pr-open · **Priority:** P1
> **Path:** spc-254 → tkt-258 → pr-269

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/258 |
| status | pr-open |
| adopted | false |
| summary | Coordinator persists DAG/layer/node/attempt/cursor; no model inference; resume after restart |
| spec | spc-254 — Executable workflow contracts (path: ../../specs/spc-254-executable-workflow-contracts.md) |
| covers | A5 |
| blocked_by | #255, #257 |
| parallel_group | l3-coordinator |
| paths | skills/batch-work/scripts/lib/coordinator.sh, skills/finish-work/**, skills/batch-work/scripts/ |
| solo_merge | yes |
| primary_ticket | tkt-258 |
| related_tickets | (none) |
| worktree_bind | tkt-258-recoverable-coordinator |
| prs | pr-269 — https://github.com/percena/lattice/pull/269 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T00:00:00Z |

## Acceptance (this slice)

- [x] **A5**
- A host restart mid-batch/finish resumes from the persisted DAG/layer/node-attempt/PID/PR/OID/marker-owner/failure-class/resume-cursor without re-deriving state from artifacts. Coordinator performs no model inference (D4). Spc-254 A5; see Spec for full text.

## Notes

- Foundation/parallel per ship plan: layer 0=(tkt-255) serial; layer 1=tkt-256/260/261; layer 2=tkt-257(after 256)/tkt-259(after 255); layer 3=tkt-258(after 255+257).
- One sibling worktree per concurrent ship slot.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/258
- Spec: `spc-254` (path above)
- Review: `rev-20260830-141357Z`

## Lineage

- Parent spec: **spc-254**
- Parent issue: **#254** (sub-issue of Spec primary)
- Primary ticket: **tkt-258**
- Covers: **A5**
- Blocked by: #255, #257
- Parallel group: l3-coordinator
- Worktree bind: tkt-258-recoverable-coordinator
- Child PRs: pr-269

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
