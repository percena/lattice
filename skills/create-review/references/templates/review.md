---
# status: open | concluded — when concluding set outcome
# kind: research (Review-only; not a GitHub issue label). Tickets use spike for time-boxed research delivery.
id: rev-YYYYMMDD-HHMMSSZ
slug: example-compare
title: Example compare
kind: research
status: open
outcome: null
summary: "≤120 chars preview"
created: YYYY-MM-DD
updated: YYYY-MM-DD
related_specs: []
related_tickets: []
related_prs: []
---

# Review: Example compare

> **TL;DR:** <one sentence — standalone; no "see chat">
> **Kind:** research · **Status:** open · **Outcome:** (set when concluding)
> **Next:** inform_only | needs_decision | spawn_spec | spawn_tickets | spawn_fix | needs_grill

<!-- required -->
## Context

Why this review exists (trigger, repo area, question). Enough that a cold reader understands the question.

<!-- required unless explicit skip — see policy Problem Audit -->
## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | Problem real? Mis-attribution? |
| Information | Enough to analyze? **Must-have** gaps? |
| Hidden issues | Related / deeper issues, or none found |
| Existing solution | Does an existing solution already meet the stated goal? If yes, surface it as the status-quo comparison row before proposing alternatives. |

- **Stop rule:** must-have info missing → do not invent solutions; keep open or lead Findings with blocked-on-info.
- **Skip:** `Skipped — <one-line reason>` when the question is already crisp (policy).

<!-- required for design/audit reviews that compare options; optional otherwise -->
## Comparison matrix

<!-- rows = proposed option / status quo / alternatives; columns = cost, code-delta, risk, constraints, capability/feature tradeoffs. Prevents weighing options by vibes / confirmation bias. -->

| Option | Cost | Code-delta | Risk | Constraints | Capability |
| --- | --- | --- | --- | --- | --- |
| Proposed option | | | | | |
| Keep status quo | | | | | |
| Alternative A | | | | | |

<!-- required -->
## Findings

1. **…** — evidence: …
2. **…**
3. **…**

Keep ≤7 findings; overflow → appendix.

<!-- recommended -->
## Recommendations

1. …

<!-- required to conclude: front matter status: concluded + exactly one outcome -->
## Outcome (required to conclude)

| outcome | When |
| --- | --- |
| `inform_only` | Knowledge only; no delivery |
| `needs_decision` | Design-level decision needed — **not terminal**; surfaces in `.lattice/reviews/needs-decision.md` triage queue; morning triage picks an option, then outcome updates to spawn_* |
| `spawn_spec` | Need a locked Spec before tickets |
| `spawn_tickets` | Scope clear; slice into issues |
| `spawn_fix` | Clear bug/fix path; Spec optional |
| `needs_grill` | Still fuzzy — run create-spec first-pass align |

### Follow-ups

- [ ] Spec `spc-…`?
- [ ] Ticket(s)?
- [ ] No action

<!-- recommended -->
## References

- Related code/docs paths examined: …
- Prior reviews/specs (if any): bare ids

## Links

Bare ids only in front matter lists (`spc-N`, not slugful).
