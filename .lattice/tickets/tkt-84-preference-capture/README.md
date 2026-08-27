# tkt-84-preference-capture

> **TL;DR:** Encode proactive preference capture as decision-policy law — the active skill writes operator-stated preferences at utterance time; user reminders defeat the file
> **Kind:** feat · **Priority:** P2
> **Path:** (ticket-only) → tkt-84 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/84 |
| status | queued |
| adopted | false |
| summary | capture INVARIANT in decision-policy + one-line wiring in start-work/finish-work/batch-work |
| spec | none — operator feedback 2026-08-26 (preferences.md meta-entry added same day) |
| covers | operator feedback: proactive preference management |
| blocked_by | (none — wave 2 scheduling only) |
| parallel_group | G1 (wave 2) |
| paths | skills/_lattice-lib/references/decision-policy.md, skills/start-work/SKILL.md, skills/finish-work/SKILL.md, skills/batch-work/SKILL.md |
| solo_merge | yes |
| **primary_ticket** | tkt-84 (this issue) |
| **related_tickets** | tkt-81 (shares the identical 0.2.3 train cut — first live train-mode exercise) |
| **worktree_bind** | tkt-84-preference-capture |
| worktree | sibling …/lattice.worktrees/tkt-84-preference-capture/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] decision-policy.md: capture INVARIANT under chain source #4 (write at utterance time, date + operator-stated provenance, direct entry — ×2 promotion is for journal-derived candidates only; one-line confirmation to the operator) + a "what counts" heuristic (durable + cross-ticket; feature-scoped → Spec Decisions; system law → ADR — capture routes, never swallows)
- [ ] start-work, finish-work, batch-work SKILL.md each carry a one-line citation of the rule (minimal, style-matched)
- [ ] validate-skills green

## Approach

decision-policy.md gains a short "Capture duty" subsection beside the resolution chain (INVARIANT + heuristic table + routing note + the existing lifecycle cross-reference). Each of the three SKILL.md files gets one DEFAULT-severity line at its natural operator-interaction point (start-work EXECUTE notes; finish-work operator-decision step; batch-work orchestrator duties). No restructuring.

## Anticipated decisions

- Exact wording of the "what counts" heuristic — disposition: agent-decides (keep to 3 rows; journal)
- Version handling — pre-resolved: do NOT bump; the orchestrator places tkt-81's identical 0.2.3 cut on this branch after the PR opens (live test of tkt-60 train mode)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Origin: operator had to remind the AI to write the CI-retry preference — the mechanism must be self-driving
- The preferences.md meta-entry (added 2026-08-26) is the interim rule; this ticket makes it law

## References

- `.lattice/preferences.md` DEFAULT §meta-entry · decision-policy.md chain source #4 · tkt-46 lifecycle header

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-84** · Parallel group: **G1 (wave 2)** · Worktree bind: `tkt-84-preference-capture`

## Finish

- (none yet)
