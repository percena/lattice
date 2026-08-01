---
# status: draft | locked | done | superseded
id: spc-N
slug: example-feature
title: Example feature
kind: feat
status: draft
mode: C
priority: P2
summary: "≤120 chars — preview"
created: YYYY-MM-DD
updated: YYYY-MM-DD
tickets: []
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Example feature

> **TL;DR:** <one sentence — artifact is readable without chat history>
> **Kind:** feat · **Status:** draft · **Mode:** C · **Priority:** P2
> **Path:** (none yet | spc-N → tkt-… → pr-…)

<!-- required -->
## Why

[Self-contained problem statement + user value. If based on a Review, cite it — do not say "as discussed".]

<!-- recommended -->
## In scope

-

<!-- recommended: what this delivery will not do -->
## Out of scope

-

<!-- required (C: use stable A* ids for light RTM; tickets declare covers) -->
## Acceptance

- [ ] **A1** <acceptance criterion>
- [ ] **A2** <acceptance criterion>

<!-- optional: long-term "we will not build this product direction" (vs Out of scope = this delivery) -->
## Non-goals

-

<!-- recommended: feature-local only. Cross-feature / system-shape → docs/adr/NNN -->
## Decisions (principal, user-confirmed)

1.

<!-- optional -->
## Agent-assumed (secondary)

-

<!-- optional; empty or explicitly accepted before status: locked; set done when delivery complete -->
## Risks / open questions

-

<!-- recommended -->
## References

[Only what this Spec reuses — explicit ids/paths]

- Review: `rev-YYYYMMDD-HHMMSSZ` → path (if any)
- Prior Spec: (none | superseded id)
- ADR: (none | `ADR-NNN` → `docs/adr/NNN-….md`)

<!-- required lists in front matter; body is recovery -->
## Links / bloodline (L0)

- Tickets: bare ids in front matter (`tkt-N`)
- PRs: prefer GitHub `Fixes`/`Refs`; Spec.prs is recovery
- Reviews: `rev-YYYYMMDD-HHMMSSZ`
