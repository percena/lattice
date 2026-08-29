---
id: spc-187
slug: hard-limit-closure
title: Hard-limit enforcement closure — machine-checked transitions, human-adjudicated escapes
kind: feat
status: locked
mode: C
priority: P1
summary: Close the enforcement asymmetry found in rev-20260829-160834Z — make the documented safety laws (batch merge gate, FSM transitions, CI gate, caps) machine-checked per the ADR-007 boundary law, with human-adjudicated exception channels.
created: 2026-08-29
updated: 2026-08-29
tickets: []
prs: []
reviews: [rev-20260829-160834Z]
supersedes: []
superseded_by: null
---

# spc-187: Hard-limit enforcement closure

> **Status:** locked (2026-08-29) — scope confirmed in the review dialogue; macro sign-off given by operator.

## Why

rev-20260829-160834Z audited the whole workflow and found a systematic asymmetry: the periphery (worktree discipline, identity binding) is machine-enforced, while the core laws are prose — the night-shift headline invariant "night states never reach merged" has **no script or hook** behind it, FSM transition legality is agent-discipline, the CI gate is prose, and caps self-reported by agents. Trust in unattended delivery requires machine-checked red lines; ADR-007 fixes the boundary law (transitions vs deliberation, human-adjudicated exceptions); this Spec delivers the closure program.

## In scope

- Machine-enforced batch merge gate + marker lifecycle semantics (A1)
- Status vocabulary single-source + stamp-pr-open side-state guard (A2)
- Spec supersede trip-time invalidation sweep (A3)
- Binder `created`/`updated` timestamps (A4)
- Staleness / water-level surfacing: pr-open aging, deferred/stuck/parked counts (A5)
- Scripted `fix_cycles` + cap-exit; CI gate with compiled infra-class waiver (A6)
- Docs repair batch: marker wording contradiction, stale comments, portability citations, FSM entry edges (A7)
- ADR-007 five-piece contract applied to every hard rule shipped here (A8)

## Out of scope

- FSM-as-data: full transition-table single-source + validator transition-replay (deferred to a follow-up spec; this Spec ships vocabulary single-sourcing only — D5)
- ID allocation cross-clone races (spc/rev/ADR); `found_by`/`escaped_from` schema enforcement; team policy flags for night PR-opening; installed-skill-tree refresh tooling

## Acceptance

- **A1** — Merge path refuses while an active `.batch-work-active` marker exists (fail-closed hook/script check, not prose); human-adjudicated escape per ADR-007; marker creation/removal/scope semantics consistent across `batch-work`/`finish-work` docs and code.
- **A2** — Ticket status vocabulary + coupled-field rules single-sourced into one machine-readable definition consumed by validator and scripts; `stamp-pr-open.sh` refuses to overwrite `parked`/`stuck`/`rework` without an explicit override; direct `queued → pr-open` jump policy decided and enforced.
- **A3** — Superseding a Spec stamps its still-active child binders `deferred` + `wait_reason: spec-superseded` at supersede time (trip-time, generalizing the tkt-136/137 principle); finish-work land-time drift check stays as backstop.
- **A4** — Ticket binder template + validator carry `created`/`updated`; status transitions stamp `updated`; time-in-state computable for in-flight tickets.
- **A5** — Morning digest and/or start-work entry surfaces pr-open aging and deferred/stuck/parked water levels with explicit thresholds (no silent pile-up).
- **A6** — `fix_cycles` incremented by script in the rework loop; exceeding the ≤2 cap forces `deep-review` class; finish-work preflight checks `gh pr checks` rollup with compiled infra-class failure detection and a stamped waiver trace (no agent adjudication of CI redness).
- **A7** — Docs repair: finish-work marker wording contradiction, `reconcile-state.sh` stale comment (588-591), portability claims vs monorepo `docs/` citations reconciled, workflow-fsm.md entry edges completed (rev `spawn_*`, verify-features, S-class fast path), amendment sediment moved out of the FSM doc into ADRs.
- **A8** — Every hard rule shipped under this Spec carries the ADR-007 five-piece contract: check, message, escape channel, structured trace, metric.

## Decisions (principal)

- **D1** — Hard-limit boundary axis = transitions vs deliberation (ADR-007 §1-3). Operator-confirmed.
- **D2** — Red-line exceptions are human-adjudicated one by one (double-confirm); agent duty = recognize → stop → present; pending is an accepted production cost; no agent self-adjudication, no default break-glass (ADR-007 §5b-5c). Operator ruling.
- **D3** — Compilable corner cases are compiled into the rule (e.g. CI infra-class failure detection), not left to per-incident judgment (ADR-007 §5a).
- **D4** — Every hard rule ships the five-piece contract: check / message / escape / trace / metric (ADR-007 §4).
- **D5** — Scope control: full FSM-as-data transition replay deferred to a follow-up spec; this Spec ships the vocabulary single-source slice only.
- **D6** — Escape frequency is the boundary sensor: per-rule escape counts surface in the morning digest (ADR-007 §8).

## References

- rev-20260829-160834Z — findings + verified evidence (this Spec's spawn source)
- ADR-007 → `docs/adr/007-hard-limit-scope-law.md` — boundary law + escape adjudication
- ADR-004 — attention contract (extended by ADR-007); ADR-006 — worktree enforcement (escape pattern generalized by ADR-007)
- spc-42 — attention loop origin; `docs/workflow-fsm.md`; `docs/morning-triage.md`
- GitHub: https://github.com/percena/lattice/issues/187
