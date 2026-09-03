# tkt-259-evidence-proof-validator-migration

> **TL;DR:** Story-header/result-JSON schema; pass proof; spc-186.prs backfill; baseline+ratchet; new warns fail CI
> **Kind:** feat · **Status:** closed · **Priority:** P1
> **Path:** spc-254 → tkt-259 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/259 |
| status | closed |
| adopted | false |
| summary | Story-header/result-JSON schema; pass proof; spc-186.prs backfill; baseline+ratchet; new warns fail CI |
| spec | spc-254 — Executable workflow contracts (path: ../../specs/spc-254-executable-workflow-contracts.md) |
| covers | A7, A8 |
| blocked_by | #255 |
| parallel_group | l2-validator |
| paths | tools/validate-lattice-artifacts.py, tools/tests/, skills/run-e2e/** |
| solo_merge | yes |
| primary_ticket | tkt-259 |
| related_tickets | (none) |
| worktree_bind | tkt-259-evidence-proof-validator-migration |
| prs | pr-267 — https://github.com/percena/lattice/pull/267 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T14:30:00Z |

## Acceptance (this slice)

- [x] **A7**
- [x] **A8**
- mirror spc-254 A* criteria for this slice; see Spec for full text.

## Notes

- Foundation/parallel per ship plan: layer 0=(tkt-255) serial; layer 1=tkt-256/260/261; layer 2=tkt-257(after 256)/tkt-259(after 255); layer 3=tkt-258(after 255+257).
- One sibling worktree per concurrent ship slot.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/259
- Spec: `spc-254` (path above)
- Review: `rev-20260830-141357Z`

## Lineage

- Parent spec: **spc-254**
- Parent issue: **#254** (sub-issue of Spec primary)
- Primary ticket: **tkt-259**
- Covers: **A7, A8**
- Blocked by: #255
- Parallel group: l2-validator
- Worktree bind: tkt-259-evidence-proof-validator-migration
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish


- pr-267 merged: 2026-08-31T04:24:26Z — https://github.com/percena/lattice/pull/267 (base merge)
- issue #259 closed: 2026-08-31T04:25:59Z — https://github.com/percena/lattice/issues/259
