# tkt-260-capability-matrix-docs

> **TL;DR:** README + workflow-fsm.md state guarantee strength per call path; no global-invariant overclaim
> **Kind:** docs · **Status:** pr-open · **Priority:** P2
> **Path:** spc-254 → tkt-260 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs,P2 |
| github | https://github.com/percena/lattice/issues/260 |
| status | pr-open |
| adopted | false |
| summary | README + workflow-fsm.md state guarantee strength per call path; no global-invariant overclaim |
| spec | spc-254 — Executable workflow contracts (path: ../../specs/spc-254-executable-workflow-contracts.md) |
| covers | A6 |
| blocked_by | (none) |
| parallel_group | l1-independent |
| paths | README.md, docs/workflow-fsm.md |
| solo_merge | yes |
| primary_ticket | tkt-260 |
| related_tickets | (none) |
| worktree_bind | tkt-260-capability-matrix-docs |
| prs | pr-264 (https://github.com/percena/lattice/pull/264) |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T12:00:00Z |

## Acceptance (this slice)

- [x] **A6**
- README + `docs/workflow-fsm.md` state guarantee strength per call path (scripted = hard gate; strict Claude PreToolUse hook = defense-in-depth; advisory/uninstalled = detection only; `python3` missing → strict fail-opens). No text claims an unconditional global invariant; the old "chain never skips a step" / "Night states never reach merged" phrasings are qualified. Cites ADR-007 §5b and `rev-20260830-141357Z` F5. `tools/tests/capability-matrix-parity.bats` guards against reversion.

## Notes

- Foundation/parallel per ship plan: layer 0=(tkt-255) serial; layer 1=tkt-256/260/261; layer 2=tkt-257(after 256)/tkt-259(after 255); layer 3=tkt-258(after 255+257).
- One sibling worktree per concurrent ship slot.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/260
- Spec: `spc-254` (path above)
- Review: `rev-20260830-141357Z`

## Lineage

- Parent spec: **spc-254**
- Parent issue: **#254** (sub-issue of Spec primary)
- Primary ticket: **tkt-260**
- Covers: **A6**
- Blocked by: (none)
- Parallel group: l1-independent
- Worktree bind: tkt-260-capability-matrix-docs
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
