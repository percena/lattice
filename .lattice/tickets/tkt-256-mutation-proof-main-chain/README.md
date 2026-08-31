# tkt-256-mutation-proof-main-chain

> **TL;DR:** Wire verify-mutation --expected-oid into create-pr/batch/delegated; proof failure halts cleanup
> **Kind:** feat · **Status:** queued · **Priority:** P1
> **Path:** spc-254 → tkt-256 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/256 |
| status | pr-open |
| adopted | false |
| summary | Wire verify-mutation --expected-oid into create-pr/batch/delegated; proof failure halts cleanup |
| spec | spc-254 — Executable workflow contracts (path: ../../specs/spc-254-executable-workflow-contracts.md) |
| covers | A2 |
| blocked_by | (none) |
| parallel_group | l1-independent |
| paths | skills/create-pr/**, skills/_lattice-lib/scripts/verify-mutation.sh |
| solo_merge | yes |
| primary_ticket | tkt-256 |
| related_tickets | (none) |
| worktree_bind | tkt-256-mutation-proof-main-chain |
| prs | pr-265 — https://github.com/percena/lattice/pull/265 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T04:07:23Z |

## Acceptance (this slice)

- [x] **A2**
- mirror spc-254 A* criteria for this slice; see Spec for full text.

## Decision journal

- 2026-08-31T04:07:23Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #265) [WARN — signal logged, not silently lost]

## Notes

- Foundation/parallel per ship plan: layer 0=(tkt-255) serial; layer 1=tkt-256/260/261; layer 2=tkt-257(after 256)/tkt-259(after 255); layer 3=tkt-258(after 255+257).
- One sibling worktree per concurrent ship slot.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/256
- Spec: `spc-254` (path above)
- Review: `rev-20260830-141357Z`

## Lineage

- Parent spec: **spc-254**
- Parent issue: **#254** (sub-issue of Spec primary)
- Primary ticket: **tkt-256**
- Covers: **A2**
- Blocked by: (none)
- Parallel group: l1-independent
- Worktree bind: tkt-256-mutation-proof-main-chain
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
