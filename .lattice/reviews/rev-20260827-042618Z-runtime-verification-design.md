---
id: rev-20260827-042618Z
slug: runtime-verification-design
title: Runtime verification loop — closing the "nothing ever runs the product" gap
kind: design
status: concluded
outcome: spawn_spec
summary: "Design for AI full-feature E2E verification: the oracle problem is already solved by Lattice lineage (Spec A* = feature inventory with expected behavior); a persistent feature map + verify-features skill on the run-e2e substrate + escaped-defect metric unblocks spc-42's trust calibration"
created: 2026-08-27
updated: 2026-08-27
related_specs: [spc-104]
related_tickets: []
related_prs: []
---

# Review: Runtime verification loop

> **TL;DR:** Every quality mechanism in the loop reads artifacts; nothing ever *runs the product* and checks behavior against expectations. The industry blocker for AI full-feature testing is the oracle problem — what features exist and what each should do — and a Lattice repo already stores the answer in Spec acceptance criteria and ticket binders. Design: a persistent, diffable **feature map** (`.lattice/feature-map.md`), a **verify-features** skill (inventory → plan → execute → triage → report) on the run-e2e/ego-browser substrate, three run-e2e upgrades, and the **escaped-defect metric** whose absence spc-42 named as its trust-calibration blocker. Also captured here: the audit-method upgrades for the review skills (operator request, ticket-only).
> **Kind:** design · **Status:** concluded · **Outcome:** spawn_spec (spc-104)
> **Next:** spc-104 → tkt-105/106/107 (+ tkt-108 ticket-only)

## Context — the operator's requirement

Vibe-coded deliveries ship real bugs that today only humans find, by hand-driving the app. AI-driven testing misses things for two reasons the operator named precisely: (1) the AI does not know **what features the system has**, and (2) it does not know **how each should be tested and what the expected result is** — so coverage is ad-hoc and un-audited. The team already uses **ego-browser** (Playwright-style facade, task-space login inheritance) and has `run-e2e` as a story-authoring pattern; what is missing is the layer above: full-feature coverage with designed pipelines and explicit expectations.

Related standing gap: `spc-42`'s auto-pass trust calibration is parked on "needs the escaped-defect metric to accumulate" (spc-42 Risks; `review-delivery` documents the metric as "a later ticket"). Runtime verification is exactly the producer of that signal.

## The design in one paragraph

The oracle problem is solved by **mining the lineage**: every Spec `A*` and ticket acceptance box is a feature with expected behavior and a citation. Persist the inventory as `.lattice/feature-map.md` — one row per feature: entry point, expected behavior (oracle) + source, mutation class, risk tier, story reference, last-verified stamp, status. A new **`verify-features`** skill owns the map (single writer) and runs a bounded loop: **INVENTORY** (lineage mining → surface scan → bounded UI crawl for undocumented features) → **PLAN** (stories per feature: happy/edge/negative; oracle policy: spec-derived > doc-derived > generic invariants) → **EXECUTE** (run-e2e heredoc stories, one Bash invocation each) → **TRIAGE** (product-bug | test-defect | environment | auth; minimal repro; bug issues + binders with Reproduction Steps that feed start-work's existing Phase 0c repro loop; escaped-defect tracing) → **REPORT** (verification rev + feature-map stamp). Every story carries a **universal invariant bundle** regardless of oracle strength: zero `pageErrors`, zero non-allowlisted `consoleErrors`, no first-party 4xx/5xx, no dead-end navigation, and **mutation round-trip** (create → reload → assert persisted — the top vibe-code bug class: the UI "succeeds" but nothing was saved).

## Key decisions

1. **Feature map is a committed artifact, not tool state.** Grep-able, diffable, reviewed in PRs — matches the "memory is an engineering artifact" philosophy. Coverage becomes explicit: a digest can say "23/31 verified, 3 fail, 5 untested" instead of vibes. Single writer: `verify-features` (others read).
2. **Oracle hierarchy.** spec-derived (A* citation — strong) > doc/README-derived (medium) > generic invariants only (weak, for crawl-discovered features — which are themselves findings: an undocumented feature is a lineage gap). Every `pass` must cite which oracle was checked; a pass with no oracle is forbidden.
3. **Safety INVARIANT — mutation policy.** The skill drives a real browser with the user's login state. Every feature row declares `mutations: none | safe | destructive`. `destructive` (delete / pay / send / external side-effects) is **never** exercised without per-feature operator authorization recorded in the map; default posture is read-only exploration plus `safe` mutations in operator-designated test environments only (`.lattice/config.yaml` e2e allowlist).
4. **Bounded, environment-honest.** Preflight fails loud when the app or ego-browser is absent (status `blocked`, never silent skip — same law as check-duplicate-work post-#99). Waves are bounded (default ≤12 stories/wave, ≤2 waves/invocation, flaky retry ≤1) per the repo's bounded-loop invariant. Not a CI job (spc-12 already noted ego-browser needs a running headed app); it is a day-phase or post-night-triage tool.
5. **Loose coupling to review-delivery.** review-delivery stays artifact-only (its INVARIANT); it may *cite* the latest verification rev, never run stories. batch-work's `--with-review` chain may optionally append a verify-features pass after the digest — separate invocation, separate report.
6. **verify-features files bugs, never fixes them.** Product edits are start-work's job; the bug binder's Reproduction Steps + evidence path plug into the existing bug-repro loop (spc-12 A3).
7. **Escaped-defect metric = artifact mechanics, no new infra.** Bug binders gain `found_by` and `escaped_from` fields (`pr-N` + the digest id that auto-passed it, traced via blame/`git log -S` → PR → digest grep). review-delivery's digest counts escapes since last digest and cumulatively per triage class, next to its existing sampling convention. A dated spc-42 amendment arms the previously-unfirable "revisit risk-tiered auto-merge once the metric exists" trigger.
8. **run-e2e stays a pattern, not a runner.** Three additive upgrades: `httpErrors` capture (subscribe `page.on('response')`/`requestfailed` for first-party 4xx/5xx — today only console/page errors are caught), a story-header convention (feature id + oracle citation + mutation class, so stories are traceable to the map and sweepable), and the mutation round-trip recipe. Story catalog: `.lattice/e2e/stories/*.story.md` in consumer repos.

## Also captured: review-skill audit upgrades (operator request, ticket-only)

The two operator-praised audit rounds used a method the review skills do not encode. Distilled into `create-review` as an audit recipe (kind: audit): **orthogonal fan-out** (parallel read-only sweeps over disjoint concerns); **verify-then-report** (every claim re-verified against the tree with file:line evidence before it enters Findings; non-reproducing claims dropped and counted); **enforcement-coverage axis** ("which check enforces this law?" — an unenforced law is itself a finding: *surfaces with a validator stay fresh, surfaces without one rot*); **claim–implementation reconciliation** (doc sentences promising tool behavior get executed against the tool); **history archaeology** (CI red-run mining + recurring-deferral mining, each finding marked already-addressed-or-not); **root-cause clustering with mechanism pairing** (every spawned ticket pairs the repair with the mechanism preventing recurrence). One line lands in review-code's docs-sync axis for the claim-reconciliation class. → tkt-108 (no spec needed; doc-law change).

## Rejected alternatives

- **YAML/step-DSL test runner** — re-litigates ADR-002 §2; the heredoc story stays the unit.
- **Coverage tracked in tool state or GitHub only** — not grep-able at L0, dies with the tool; the committed map is the Lattice way.
- **Wiring runtime testing into review-delivery as a fifth axis** — breaks its artifact-only INVARIANT and its "never edits, never runs product" posture; loose coupling via citation instead.
- **Auto-fixing found bugs in the same pass** — collapses tester and implementer accountability; bug → ticket → start-work keeps the chain.

## References

- Operator requirement (2026-08-27, this session) · spc-42 Risks · `review-delivery` §Trust calibration · `run-e2e` SKILL.md · ADR-002 §2 (ego-browser foundation) · spc-12 A3/A4 (bug-repro loop, run-e2e origin)
