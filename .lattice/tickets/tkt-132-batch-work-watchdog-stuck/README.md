# tkt-132-batch-work-watchdog-stuck

> **TL;DR:** batch-work stamps stuck+wait_reason:unblock on watchdog-timeout at trip time so binder SoT reflects "abandoned" not "active" (FSM-2b)
> **Kind:** feat · **Priority:** P2
> **Path:** rev-20260827-102420Z → tkt-132 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/132 |
| status | queued |
| adopted | false |
| summary | Stamp stuck+wait_reason on watchdog-timeout (FSM-2b in-progress recovery) |
| spec | none — ticket-only from rev-20260827-102420Z F2 |
| covers | rev F2 |
| blocked_by | (none) |
| parallel_group | G2 (serial with tkt-135 on docs/workflow-fsm.md) |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md, docs/workflow-fsm.md, skills/start-work/SKILL.md |
| solo_merge | yes (one-PR with tkt-135) |
| **primary_ticket** | tkt-132 (this issue) |
| **related_tickets** | tkt-135 (G2 serial, same PR) |
| **worktree_bind** | tkt-132-batch-work-watchdog-stuck |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** batch-work stamps stuck+wait_reason:unblock on watchdog-timeout at trip time
- [ ] **A2** docs/workflow-fsm.md transition table + mermaid include in-progress → stuck (watchdog-timeout/abandonment)
- [ ] **A3** start-work resume documents the in-progress interruption case
- [ ] **A4** bats: watchdog-timeout fixture leaves binder at stuck (not in-progress)

## Approach

In batch-work flow.md WATCHDOG/TIMEBOX section: at trip time, the host stamps the binder status: stuck + wait_reason: unblock (precedent: in-progress → stuck when fallback bounds hit, workflow-fsm.md:101 — agent-stampable). This makes the binder SoT honest ("needs human") and routes morning triage through the existing stuck exits. Add the in-progress → stuck edge to workflow-fsm.md mermaid + table. In start-work resume enumeration (:87-90), add the in-progress case: "interrupted/abandoned in-progress → treat as stuck, route through stuck exits."

## Anticipated decisions

- Whether stuck is the right enum vs. a new abandoned value — disposition: pre-resolved (reuse stuck; no new enum values, per ADR-004 §6)
- Whether to also stamp on crash (not just timeout) — disposition: agent-decides (crash detection is host-level; stamp if detectable)

## References

- GitHub issue body is SoT for long prose
- Review: rev-20260827-102420Z (Finding 2 / FSM-2b)
- Prior: rev-20260827-064527Z (FSM-2 — fuse-halt, the sibling)
- ADR: ADR-004 §5 (bounded loops), §6 (binder SoT)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-132 · Parallel group: G2 · Worktree bind: tkt-132-batch-work-watchdog-stuck

## Finish

- (none yet)
