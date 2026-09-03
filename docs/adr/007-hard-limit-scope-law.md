# ADR 007: Hard-limit scope law — constrain transitions, free deliberation; compiled corner cases, human-adjudicated exceptions

- **Status:** Accepted
- **Date:** 2026-08-29
- **Deciders:** operator, Claude
- **Related:** spc-186, rev-20260829-160834Z

## Context

Lattice began advisory-first by design: constrain nothing an agent does, so as
not to dull its creative reasoning. Experience showed a class of **basic
disciplines** that agents violate repeatedly (worktree location, state
stamping, merge authority), which pushed the project toward hard enforcement
(ADR-006). `rev-20260829-160834Z` then found the resulting state
**asymmetric**: the periphery is machine-enforced (worktree/write gates) while
the core is prose-only — the batch merge gate ("night states never reach
merged"), FSM transition legality, the CI gate, and retry/fix caps have no
mechanical enforcement at all.

That review left the boundary question open: which rules deserve hard limits,
and what happens at the corner cases? The operator's constraint: **red-line
exception adjudication is always human** — company-governance model, where
exceptions are approved one by one, never self-authorized, even with a paper
trail. A task forced to wait for that adjudication is an accepted production
cost.

## Decision Drivers

- LLM capability profile: attention dilution over long context; multi-constraint
  compliance decays sublinearly; self-bookkeeping and counting are unreliable
  across compaction/interruption; advisory violations fail **silently**, while
  agents adapt excellently to **loud** tool-level refusals; multi-agent fan-out
  multiplies the per-night violation expectation.
- Goodhart: hard-enforcing a non-decidable rule produces checkbox compliance —
  the agent learns to satisfy the checker, not the goal.
- Autonomy economics: longer unattended runs raise per-violation cost;
  generation gets cheaper while verification does not, raising the relative
  value of machine-checked invariants.
- Attention budget conservation: every prose rule consumes instruction-following
  budget; moving a rule into a hook removes it from the model's cognitive load.

## Considered Options

1. **Maximal hard enforcement, no escapes** — rejected: decidable-but-unlucky
   corner cases (e.g. CI red for billing reasons, not code reasons) deadlock the
   pipeline; brittle.
2. **Advisory-only** — rejected: the original design; observed repeated silent
   violations under long context and night fan-out.
3. **Hard blocks + agent self-adjudicated escape with trace** — rejected: the
   same pressure dynamics that cause silent violations also rationalize escapes;
   self-adjudication of red lines is unacceptable even with a trace.
4. **Chosen** — the boundary law below.

## Decision

1. **Boundary axis: transitions vs deliberation.** Hard limits constrain changes
   to durable state (branch/worktree creation, binder status transitions, PR
   open/merge, artifact writes) — never the content of thinking (design,
   implementation, debugging approach, question phrasing).
2. **2×2 placement.** (decidable × high-cost) → machine-enforce;
   (semantic × high-cost) → human-owned (ADR-004 whitelist);
   (decidable × low-cost) → automate silently or warn;
   (semantic × low-cost) → leave free.
3. **Decidability prerequisite.** A rule may be hard-enforced only if a machine
   can recognize its violation without ambiguity. Important-but-undecidable
   rules stay advisory + human review; do not build checkers that invite gaming.
4. **Every hard rule ships five pieces:** check (script), message (the rule, why
   it exists, the legal escape), escape channel, structured trace, metric. A
   hard rule without all five is not done.
5. **Corner cases take one of three channels:**
   - **a. Compilable → compile into the rule.** If the corner case is itself
     machine-decidable, the rule absorbs it (e.g. a CI gate distinguishes
     infra-class failures — billing/quota/timeout — from real failures;
     infra-only red + local verification evidence passes with an auto-stamped
     waiver). This is rule precision, not an exception.
   - **b. Genuine exception → human adjudication, one by one.** The agent's duty
     is *recognize → stop → present the case*; adjudication is always human
     (double-confirm). If no human is available (night), the task pends —
     `parked`/`stuck` are first-class M2 states and morning triage is the
     adjudication venue. Pending is an accepted cost of production safety.
   - **c. No agent self-adjudication of red lines; no default break-glass.**
     Human-approved escapes execute via `--reason "user-authorized: …"`, and the
     authorization is part of the trace.
6. **Escape traces are structured and live in the protected artifact** (binder
   `## Decision journal` / `## Finish` ledger): rule id, reason, authorizer,
   timestamp. Chat is not a trace.
7. **Exception recurrence feeds M3.** A repeatedly approved exception is
   proposed for preference promotion (the existing ×2 ratification path) or for
   compilation into the rule (5a). Exception frequency should decline over time;
   the double-confirm mechanism itself is permanent.
8. **Escape metrics are the boundary sensor.** Per-rule escape counts surface in
   the morning digest. A high escape rate means the boundary is misplaced —
   redraw it or demote the rule to advisory; sustained zero means healthy.
9. **Message quality is first-class.** A block message must state the rule, its
   purpose, and the legal escape. High false-positive rates teach agents to
   route around hooks; channel 5a is the primary defense.

## Consequences

- Positive: the enforcement asymmetry becomes a defined closure program
  (spc-186); every new hard rule has a done-definition; night autonomy is
  bounded without deadlock — no silent red-line crossings, no wedged corner
  cases; escape data gives an empirical loop for boundary calibration.
- Negative: each hard rule costs more to ship (five pieces), so the 2×2 gate
  must be applied honestly; human attention is the bottleneck for exceptions
  (mitigated by 5a compilation and 7 promotion).
- Extends, does not amend: ADR-004's human-owned whitelist gains the
  exception-adjudication duty (5b); ADR-006's `--allow-* --reason` escape
  pattern becomes one instance of the general five-piece contract.

## Status history

- 2026-08-29 — Accepted (design dialogue, rev-20260829-160834Z; operator approved the boundary law and the human-adjudication amendment).

## Notes

- The inventory of prose-only rules this law must absorb (merge gate, CI gate,
  FSM transition legality, fallback/fix caps, capture/observation duty, …) is
  tabulated in `rev-20260829-160834Z` F3; the delivery split is spc-186.

> ADR is out-of-band (not a Lattice lineage node): cite as `ADR-NNN` / path, not as lineage edges.
