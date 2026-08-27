---
id: spc-104
slug: runtime-verification
title: Runtime verification loop — feature map, verify-features skill, escaped-defect metric
kind: feat
status: locked
mode: C
priority: P1
summary: "AI full-feature E2E verification: persistent feature map with lineage-derived oracles, a verify-features skill on the run-e2e/ego-browser substrate, run-e2e capture/traceability upgrades, and the escaped-defect metric that unblocks spc-42's auto-pass trust calibration"
created: 2026-08-27
updated: 2026-08-27
tickets: [tkt-105, tkt-106, tkt-107]
prs: []
reviews: [rev-20260827-042618Z]
supersedes: []
superseded_by: null
---

# Spec: Runtime verification loop

Primary issue: **#104** (epic). Design rationale: `rev-20260827-042618Z`.

## Why

Every quality mechanism in the loop reads artifacts; nothing ever runs the product and checks behavior against expectations. Vibe-coded deliveries therefore leak bugs that only humans find by hand-driving the app. The industry blocker — the oracle problem (what features exist, what should each do) — is already solved in a Lattice repo: Spec `A*` criteria and ticket acceptance are a feature inventory with expected behavior and citations. Turning that into a runtime loop also produces the escaped-defect signal spc-42 parked its auto-pass trust calibration on.

## In scope

- `.lattice/feature-map.md` — committed, diffable feature inventory with oracles, mutation classes, risk tiers, verification stamps; single writer `verify-features`; template + format check in the artifacts validator.
- `verify-features` skill (14th user-facing): INVENTORY → PLAN → EXECUTE → TRIAGE → REPORT, on run-e2e stories; bug filing into the existing bug-repro loop; bounded; environment-honest; mutation-safe.
- `run-e2e` upgrades: `httpErrors` capture, story header (feature id + oracle citation + mutation class), mutation round-trip recipe, story catalog convention (`.lattice/e2e/stories/`).
- Escaped-defect metric mechanics: bug-binder `found_by` / `escaped_from` fields + tracing recipe + digest counting in review-delivery; dated spc-42 amendment arming its parked revisit trigger.

## Out of scope

- A YAML/step-DSL runner (ADR-002 §2 stands); CI execution of browser stories (needs a running headed app — day-phase / post-night tool); auto-fixing found bugs (bug → ticket → start-work); risk-tiered auto-merge itself (spc-42 out-of-scope; this spec only arms its metric trigger); visual-pixel regression and load/perf testing.

## Decisions

1. **Oracle hierarchy (INVARIANT):** spec-derived > doc-derived > generic invariants; every `pass` cites the oracle checked; a pass without an oracle is forbidden. Crawl-discovered features get generic invariants only, and their existence is itself a lineage-gap finding.
2. **Universal invariant bundle (DEFAULT):** every story asserts zero `pageErrors`, zero non-allowlisted `consoleErrors`, no first-party 4xx/5xx (`httpErrors`), no dead-end navigation; mutation stories assert the round-trip (create → reload → verify persisted).
3. **Mutation policy (INVARIANT):** per-feature `mutations: none | safe | destructive`; `destructive` never exercised without per-feature operator authorization recorded in the map; `safe` mutations only in operator-designated e2e environments (`.lattice/config.yaml` allowlist); default posture read-only.
4. **Bounds (INVARIANT):** preflight fails loud (app/ego-browser absent → `blocked`, never silent); ≤12 stories/wave, ≤2 waves/invocation, flaky retry ≤1 (config-tunable).
5. **Coupling (DEFAULT):** review-delivery stays artifact-only and may cite the latest verification rev; batch-work `--with-review` may chain a verify-features pass as a separate invocation.
6. **Metric mechanics (DEFAULT):** `escaped_from` = `pr-N — digest rev-… (auto-pass)`, traced via blame/`git log -S` → PR → digest grep; digest reports per-class escape counts beside the existing sampling convention.

## Acceptance

- [ ] **A1** `.lattice/feature-map.md` template + conventions exist (`_lattice-lib` template; columns: id, feature, entry, oracle + source, mutations, risk, story, last-verified, status ∈ untested|pass|fail|blocked); `validate-lattice-artifacts.py` checks format + status vocabulary when the file exists (with fixture-backed tests)
- [ ] **A2** `verify-features` skill ships: SKILL.md + references (inventory recipe incl. lineage mining and bounded crawl; story/oracle design policy incl. the invariant bundle; triage + bug-filing recipe wiring Reproduction Steps into start-work Phase 0c; report/rev shape) with the INVARIANTs of Decisions 1/3/4; registered on every surface the validator enforces (manifests keywords, plugin README, README tables + zh, llms.txt, routing catalog + eval cases, getting-started)
- [ ] **A3** `run-e2e` upgrades land: `httpErrors` in the JSON schema + subscription pattern, story header convention, mutation round-trip recipe, story catalog convention — SKILL.md + story-template + example updated coherently
- [ ] **A4** escaped-defect mechanics land: ticket-binder template optional `found_by`/`escaped_from` fields, tracing recipe, review-delivery digest escape-count block beside the sampling convention, dated spc-42 Risks amendment arming the revisit trigger
- [ ] **A5** full `ci-local` green on each slice; version train 0.3.0 (new skill = minor) with one shared cut

## Ship plan

Stacked train on the round-5 PRs (#97–#103): planning PR (this file + rev + binders) first, then tkt-105 (A1+A2, owns the 0.3.0 cut + CHANGELOG), tkt-106 (A3), tkt-107 (A4). tkt-106/107 carry the cut byte-identically. Merge order: round-5 → planning → 105 → 106/107 (106 and 107 path-disjoint, any order). Merges are the operator's.

## Risks / open questions

- Ego-browser behavior under a fully unattended crawl (dialog storms, infinite scroll surfaces) — mitigated by crawl bounds + read-only default; observe in first field runs.
- Feature-map staleness between runs — mitigated by the `last-verified` stamp making staleness visible and by the INVENTORY diff step; a freshness warning in the validator is a candidate follow-up, deliberately not in scope.
- Oracle quality for legacy consumer repos with no Lattice lineage — the map still works (doc-derived + generic tiers), but expectations are weaker; documented in the skill, not solvable here.

## References

- `rev-20260827-042618Z` (design) · spc-42 Risks + review-delivery §Trust calibration (metric hook) · ADR-002 §2 (ego-browser foundation) · spc-12 A3/A4 (bug-repro loop, run-e2e)
