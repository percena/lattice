# tkt-90-binder-lifecycle-closure

> **TL;DR:** Make the binder FSM terminal state reachable (finish-ledger flips every working status), give the validator eyes for the breach (inverse + duplicate-id checks), restamp the 19 stranded binders, and make workflow-fsm/ADR-004 claims honest
> **Kind:** fix · **Priority:** P1
> **Path:** (ticket-only) → tkt-90 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/90 |
| status | queued |
| adopted | false |
| summary | finish-ledger status flip for all working statuses + validator finish_without_terminal_status / duplicate_ticket_id + restamp + doc-claim honesty |
| spec | none — audit rev-20260827-033352Z F1/F2/F8 |
| covers | audit F1, F2, F8 (spc-12 land-stamp, tkt-65 box, tkt-35 collision) |
| blocked_by | (none) |
| parallel_group | G1 (wave 1) |
| paths | skills/_lattice-lib/scripts/finish-ledger.sh, tools/validate-lattice-artifacts.py, .lattice/tickets/**, .lattice/specs/spc-12*, docs/workflow-fsm.md, docs/adr/004*, skills/finish-work/scripts/tests/**, tools/tests/** |
| solo_merge | yes |
| **primary_ticket** | tkt-90 (this issue) |
| **related_tickets** | tkt-91 (stacked on this branch — shares finish-ledger.sh + validator), tkt-44/tkt-63 (the two round-1 tickets that broke each other) |
| **worktree_bind** | tkt-90-binder-lifecycle-closure |
| worktree | sibling …/lattice.worktrees/tkt-90-binder-lifecycle-closure/ |
| prs | (none yet) |

## Acceptance (this slice)

- [ ] **A1** `finish-ledger.sh` flips any working status (`open`, `in-progress`, `pr-open`, `rework`) to `closed` under the same close conditions; bats covers the `pr-open` fixture path
- [ ] **A2** `validate-lattice-artifacts.py` gains `finish_without_terminal_status` (error) and `duplicate_ticket_id` (error); bats coverage for both
- [ ] **A3** 19 stranded binders restamped `closed`; `tkt-35-*` collision resolved (journaled mechanism); `spc-12` land-stamped; `tkt-65:34` re-checked
- [ ] **A4** `docs/workflow-fsm.md:142` + ADR-004 §6 claims match what is actually validated
- [ ] **A5** full `ci-local` green; validator zero errors repo-wide after restamp

## Approach

Widen the status regex in finish-ledger's embedded python to a working-status alternation sourced from the same vocabulary the validator uses; extend the close-condition comment to state the law. Add the two validator findings beside `closed_without_finish` (reuse `has_finish_ledger`; parse `merged:` lines for the inverse; collect `tkt-N` prefixes across binder dirs for duplicates). Restamp = mechanical edit of 19 field tables + spc-12 stamp + tkt-65 box. Fix workflow-fsm.md's "rejects illegal transitions" to name the real checks (vocabulary + coherence: closed⇒Finish, Finish-merged⇒closed, duplicate ids) and add a dated amendment line to ADR-004 §6. Also reconcile the M3 edge notes owned here (rework → pr-open from start-work:88; pr-88 direct-capture edge) since workflow-fsm.md is in-paths.

## Anticipated decisions

- tkt-35 collision mechanism — disposition: agent-decides (renaming a historical dir breaks grep-lineage; prefer marking the older binder with an alias/duplicate note + validator allowlist-by-annotation; journal)
- Whether `rework` counts as flippable at ledger time — disposition: agent-decides (yes: a merged Finish on a rework binder is still terminal; journal)
- ADR-004 edit form — pre-resolved: dated amendment note, never rewrite the accepted text (ADR discipline)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Origin: operator-requested audit 2026-08-27; the "zero warnings repo-wide" milestone in rev-20260827-023130Z was a coverage artifact of the missing inverse check
- The 19: tkt-44, 46, 47, 48, 49, 50, 60, 61, 62, 63, 64, 65, 73, 74, 75, 80, 81, 82, 84

## References

- `.lattice/reviews/rev-20260827-033352Z-post-round4-verified-audit.md` F1/F2/F8 · spc-42:76 (SoT law) · `finish-work/SKILL.md:111`

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-90** · Parallel group: **G1 (wave 1)** · Worktree bind: `tkt-90-binder-lifecycle-closure`

## Finish
