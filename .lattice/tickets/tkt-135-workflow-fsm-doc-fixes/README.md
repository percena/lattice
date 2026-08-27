# tkt-135-workflow-fsm-doc-fixes

> **TL;DR:** Two small workflow-fsm.md doc fixes — M1 row missing Spec done terminal; mermaid missing any → closed
> **Kind:** docs · **Priority:** P3
> **Path:** rev-20260827-102420Z → tkt-135 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | documentation, P3 |
| github | https://github.com/percena/lattice/issues/135 |
| status | pr-open |
| adopted | false |
| summary | M1 row add Spec done terminal + mermaid any→closed (F5+F6) |
| spec | none — ticket-only from rev-20260827-102420Z F5+F6 |
| covers | rev F5, F6 |
| blocked_by | (none) |
| parallel_group | G2 (serial with tkt-132 on docs/workflow-fsm.md) |
| paths | docs/workflow-fsm.md |
| solo_merge | no (one-PR with tkt-132) |
| **primary_ticket** | tkt-135 (this issue) |
| **related_tickets** | tkt-132 (G2 serial, same PR) |
| **worktree_bind** | tkt-135-workflow-fsm-doc-fixes |
| prs | pr-142 — https://github.com/percena/lattice/pull/142 |

## Acceptance (this slice)

- [x] **A1** M1 row lists done as terminal; superseded documented as revision path
- [x] **A2** M1 diagram shows Spec locked → done
- [x] **A3** M2 mermaid shows any → closed (cancel) or annotation that table is authoritative
- [x] **A4** Revision propagation to existing ticket/binders documented (≥1 line)

## Approach

Edit docs/workflow-fsm.md: M1 states row (:12) add → Spec done; M1 diagram (:20-28) add Spec locked → done; document Spec locked → Spec revised (supersede by new spc-N) with propagation note (old Spec ticket/binders obsolete; finish-work land-time drift catches deviations); M2 mermaid (:32-51) add any → closed (cancel) or annotate table is authoritative.

## Anticipated decisions

- (none — pure doc, no decisions)

## References

- GitHub issue body is SoT for long prose
- Review: rev-20260827-102420Z (Findings 5 + 6)
- Evidence: finish-work/SKILL.md:70,113,220; spc-116 front matter status: done

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-135 · Parallel group: G2 · Worktree bind: tkt-135-workflow-fsm-doc-fixes

## Finish

- (none yet)
