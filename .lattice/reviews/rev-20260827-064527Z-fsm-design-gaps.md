---
id: rev-20260827-064527Z
slug: fsm-design-gaps
title: M2 FSM design gaps — SoT honesty after fuse/block + parked→queued atomicity
kind: design
status: concluded
outcome: inform_only
summary: "State-machine audit of dev pull 8447271..c2d27be surfaced two design-philosophy gaps (FSM-2, FSM-4) not actionable as code fixes; filed for team decision"
created: 2026-08-27
updated: 2026-08-27
related_specs: [spc-42]
related_tickets: [tkt-121, tkt-122, tkt-123]
related_prs: []
---

# Review: M2 FSM design gaps — SoT honesty + parked atomicity

> **TL;DR:** A state-machine audit of the dev pull (`8447271..c2d27be`) surfaced six FSM gaps. Four are actionable as code/doc tickets (`tkt-121`, `tkt-123`); this note captures the two that are **design-philosophy** rather than code defects and need a team decision before they become tickets.

## Context

The M2 execution machine (`docs/workflow-fsm.md`) couples a binder `status` field (SoT, ADR-004 §6) with a batch-report vocabulary and skill-side transition actions. The audit found two places where the **design** trades SoT honesty or atomicity for FSM cleanliness — and neither has a clear code fix without a policy decision.

## Finding 1 — FSM-2: SoT lies about schedulability after a fuse halt / dependency failure

**Where:** `skills/batch-work/references/flow.md:191,251`; `skills/batch-work/SKILL.md:61,214`.

**The gap.** A batch-work fuse halt or a `blocked-by-failure` dependency skip is **report-level only** — the affected ticket's binder `status` stays `queued` (the design explicitly refuses to "invent new enum values"; `deferred` is the optional human deschedule stamp). But the binder is the SoT (ADR-004 §6), and the batch report is ephemeral. A later **unattended** batch re-run reads only binders → sees `queued` → re-spawns a ticket whose blocker is still failed, or a ticket that was fuse-halted.

`deferred` is the human escape, but the entire point of the night shift is unattended. The design creates a window where the SoT says "schedulable" and the real state is "not schedulable."

**Why it's design, not code.** The refusal to add `blocked-by-failure`/`fuse-halted` to the binder enum is a deliberate cleanliness choice (the FSM stays small; the report carries the ephemeral state). Resolving it requires a policy call, not a one-liner:
- Option A: accept `blocked-by-failure`/`fuse-halted` as binder enum values (honest SoT; larger FSM; needs validator + template + transition-table updates).
- Option B: have batch-work stamp `deferred` (with a reason) on fuse-halted/blocked tickets at trip time so the SoT reflects "not schedulable" — but `deferred → queued` is a human transition, so this is the agent doing a human-owned stamp.
- Option C: have batch-work read the prior batch report before spawning (cross-report state) — but reports are not durable SoT and may not exist.
- Option D: leave as-is; document that fuse-halted tickets require a human to stamp `deferred` before the next unattended run (accept the gap, narrow it with a checklist).

**Severity:** medium. It wastes night compute on dead-ends and can mask a persistently-failed base, but it does not corrupt lineage or merge wrong code.

## Finding 2 — FSM-4: `parked → queued` atomicity is a "never" claim with no enforcement

**Where:** `docs/workflow-fsm.md` (transition table + §5); `skills/start-work/SKILL.md:89`.

**The gap.** The doc states ratification "atomically writes the decision into `## Decision journal` **and** flips `parked → queued` (one write — never a re-queued binder without its recorded decision)." But a Markdown file edit is **not atomic**. An agent or editor crash between the journal write and the status flip yields either (a) `parked` + journal entry (recoverable) or (b) `queued` + no journal entry — the exact "never" state.

`validate-lattice-artifacts.py` only checks static snapshots; it does **not** verify "a `queued` binder that was previously `parked` carries a journal entry" (and cannot, from a single snapshot, know prior state). The "never" is a bare claim with no machine enforcement.

**Why it's design, not code.** True atomicity needs a transaction the Markdown substrate doesn't provide. Options:
- Option A: a small script `ratify.sh` that writes both edits in one `git`-tracked commit (still not crash-atomic between the two file writes, but narrows the window and makes the pair a reviewable unit).
- Option B: a validator invariant "a binder with `## Pending decisions` empty AND `status: queued` that has **any** `## Decision journal` entry added since the last snapshot is fine; a `queued` binder whose `## Pending decisions` was emptied but `## Decision journal` gained no entry in the same diff = drift" — requires snapshot diffing, which the validator explicitly avoids ("does not replay transition history").
- Option C: accept the claim is soft; document it as a known limitation (the crash window is narrow; recovery is "check the journal").

**Severity:** medium-low. The crash window is narrow and recovery is trivial (read the binder), but the "never" language overstates the guarantee.

## Outcome

`inform_only` — these need a team policy decision (Option A/B/C/D for each) before they become actionable tickets. The actionable FSM gaps (FSM-1 counter, FSM-3 rework edges, FSM-6 wait-reason) are filed as `tkt-123`; the code-level bugs as `tkt-121`/`tkt-122`. If the team picks options for FSM-2/FSM-4, file follow-up tickets under a Spec/ADR amendment to ADR-004.

## Related

- `spc-42` (attention loop — where the FSM + SoT claims originate)
- ADR-004 §6 (binder status is SoT) + §1 (human-owned transition white-list)
- `docs/workflow-fsm.md` §2 (transition table), §5 (where M2 state lives — the "does not replay history" caveat)
- `tkt-123` (actionable FSM observability ticket)
