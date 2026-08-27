# tkt-137-fsm2-option-b-deferred-stamp

> **TL;DR:** batch-work stamps deferred+reason on fuse-halt/blocked-by-failure at trip time (FSM-2 Option B, chosen in tkt-136)
> **Kind:** feat · **Priority:** P2
> **Path:** rev-20260827-064527Z → tkt-136 (decision) → tkt-137 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/137 |
| status | queued |
| adopted | false |
| summary | Stamp deferred+reason on fuse-halt/blocked-by-failure at trip time (FSM-2 Option B) |
| spec | none — ticket-only from tkt-136 decision |
| covers | rev FSM-2 |
| blocked_by | (none) |
| parallel_group | G2 (serial with tkt-132/tkt-135 on docs/workflow-fsm.md + batch-work) |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md, docs/workflow-fsm.md |
| solo_merge | no (one-PR with G2 set) |
| **primary_ticket** | tkt-137 (this issue) |
| **related_tickets** | tkt-132 (G2 serial), tkt-135 (G2 serial) |
| **worktree_bind** | tkt-137-fsm2-option-b-deferred-stamp |
| prs | (none) |

## Acceptance (this slice only)

- [ ] **A1** batch-work stamps deferred+reason on fuse-halted tickets at trip time (not stay queued)
- [ ] **A2** batch-work stamps deferred+reason blocked-by-failure on skipped dependents
- [ ] **A3** docs/workflow-fsm.md fuse-halt note updated; no longer says stay queued
- [ ] **A4** bats: fuse-halt fixture leaves binder at deferred (not queued)

## Approach

In batch-work flow.md FUSE CHECK + NEXT-LAYER DEPENDENCY CHECK: at trip time, stamp affected binders status: deferred + a reason row (fuse-halt | blocked-by-failure). The deferred → queued re-schedule remains human (morning triage stamps queued after fixing the blocker). Update workflow-fsm.md M2 fuse-halt note (§1 + §2 table) from stay queued to stamps deferred at trip time. No new enum values (deferred exists). Validator already accepts deferred.

## Anticipated decisions

- Whether to add a reason sub-field to the binder (deferred_reason) — disposition: agent-decides (reversible; a Notes line or a wait_reason-like row; prefer reusing wait_reason semantics extended to deferred)

## References

- Decision: tkt-136 (FSM-2 = Option B), ADR-004 Amendment (tkt-136)
- Reviews: rev-20260827-064527Z (Finding 1), rev-20260827-102420Z (Finding 7)
- ADR: ADR-004 §6

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-137 · Parallel group: G2 · Worktree bind: tkt-137-fsm2-option-b-deferred-stamp

## Finish

- (none yet)
