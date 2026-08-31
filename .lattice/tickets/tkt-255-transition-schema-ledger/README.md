# tkt-255-transition-schema-ledger

> **TL;DR:** Machine-readable transition schema is SoT; one transition API + ledger; docs parity-tested
> **Kind:** feat · **Status:** pr-open · **Priority:** P1
> **Path:** spc-254 → tkt-255 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/255 |
| status | pr-open |
| adopted | false |
| summary | Machine-readable transition schema is SoT; one transition API + ledger; docs parity-tested |
| spec | spc-254 — Executable workflow contracts (path: ../../specs/spc-254-executable-workflow-contracts.md) |
| covers | A3, A4 |
| blocked_by | (none) |
| parallel_group | foundation(serial) |
| paths | skills/_lattice-lib/scripts/lib/status_vocab.py, new ledger, docs/workflow-fsm.md, tools/validate-lattice-artifacts.py |
| solo_merge | yes |
| primary_ticket | tkt-255 |
| related_tickets | (none) |
| worktree_bind | tkt-255-transition-schema-ledger |
| prs | pr-263 — https://github.com/percena/lattice/pull/263 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T03:10:00Z |

## Acceptance (this slice)

- [x] **A3** machine-readable schema (lib/transition_table.py) is SoT; transition-api.py is the single chokepoint writers call (stamp-pr-open wired); validate-lattice-artifacts.py replays per-ticket ledgers and rejects illegal edges between legal snapshots (illegal_transition_edge). Code-review F1-F8 fixed.
- [x] **A4** docs/workflow-fsm.md §2 M2 edges parity-tested against the schema (transition-parity.bats); lib==validator set-equal; ESCAPE_REQUIRED set-equal.
- mirror spc-254 A* criteria for this slice; see Spec for full text.

## Notes

- Foundation/parallel per ship plan: layer 0=(tkt-255) serial; layer 1=tkt-256/260/261; layer 2=tkt-257(after 256)/tkt-259(after 255); layer 3=tkt-258(after 255+257).
- One sibling worktree per concurrent ship slot.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/255
- Spec: `spc-254` (path above)
- Review: `rev-20260830-141357Z`

## Lineage

- Parent spec: **spc-254**
- Parent issue: **#254** (sub-issue of Spec primary)
- Primary ticket: **tkt-255**
- Covers: **A3, A4**
- Blocked by: (none)
- Parallel group: foundation(serial)
- Worktree bind: tkt-255-transition-schema-ledger
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish


- pr-263 merged: 2026-08-31T03:13:25Z — https://github.com/percena/lattice/pull/263 (base merge)
- issue #255 closed: 2026-08-31T03:13:38Z — https://github.com/percena/lattice/issues/255
