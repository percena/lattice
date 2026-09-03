---
id: rev-20260829-160834Z
slug: workflow-fsm-hardlimit-review
title: "Workflow/FSM review — enforcement asymmetry, FSM gaps, and the hard-limit boundary law"
kind: audit
status: concluded
outcome: spawn_spec
summary: "Whole-workflow audit of the Lattice delivery loop and its three coupled state machines. Core finding: enforcement is asymmetric — worktree discipline is machine-enforced (ADR-006) while the FSM core and the night-merge safety invariant remain prose. Boundary question (what deserves hard limits) resolved as a design law: constrain transitions, liberate deliberation; decidability is the prerequisite for enforcement; red-line exceptions are always human-adjudicated (double-confirm); compilable corner cases are compiled into rules, not escaped. Law promoted to ADR-007; closure program spawned as spc-186."
created: 2026-08-29
updated: 2026-08-29
related_specs: [spc-186, spc-42, spc-145]
related_tickets: [tkt-90, tkt-132, tkt-136, tkt-137, tkt-179]
related_prs: []
---

## Problem

Operator asked for a full review of the Lattice workflow itself — the three coupled state machines (M1 planning / M2 execution / M3 knowledge, `docs/workflow-fsm.md`) — with two questions: (1) what can be improved in the core workflow, and (2) where is the correct boundary for hard (machine-enforced) limits, given the project's evolution from advisory-only toward selective hard enforcement. Method: first-hand reading of README, workflow-fsm.md, day-phase.md, morning-triage.md, ADR index, CLAUDE.md; three parallel exploration passes over the six delivery-loop skills, `_lattice-lib` scripts + plugin hooks + tests, and the `.lattice` data model; then direct verification of every load-bearing claim against the code (grep/sed, this checkout).

## Findings

### F1 — The headline safety invariant is prose-only (P0)

"Night states never reach merged" (`docs/workflow-fsm.md:147`) is documented as fail-closed but has no enforcement wiring. Evidence: `grep -rn batch-work-active` across `skills/`, `plugins/`, `tools/` (excluding tests) hits only `plugins/lattice/hooks/README.md` (documentation), `plugins/lattice/hooks/lib/intercept-gh-pr-common.sh:39` and `skills/finish-work/scripts/check-pr-context.sh:44` — both merely whitelist the marker file in uncommitted-change counting, **not** merge checks. `skills/batch-work/` has no `scripts/` directory at all. The merge hook (`intercept-gh-pr-merge.sh`) does not inspect the marker. Compounding it, `skills/finish-work/SKILL.md:60,83,105` says the marker refuses merge while `:106` says "remove the marker after a successful human-driven merge" — but the gate requires the marker to be *absent before* merge, and `cleanup-workspace.sh` never references it (the marker dies only as a side effect of worktree removal). Gate semantics, location, and removal ownership are all undefined in code.

### F2 — FSM transition legality is agent-procedural (P0)

Only three binder-status transitions are scripted and atomic: `parked → queued` (`ratify.sh`), `* → pr-open` (`stamp-pr-open.sh`), `* → closed` (`finish-ledger.sh`). Everything else (`queued → in-progress`, `pr-open → rework`, `rework → in-progress → pr-open`, batch `stuck`/`deferred` stamps) is agent-procedural prose. `tools/validate-lattice-artifacts.py` validates snapshots, never replayed edges — `docs/workflow-fsm.md:156` admits this honestly. Two concrete holes verified: `stamp-pr-open.sh:346-347` guards only `closed`, so a new PR silently overwrites `parked`/`stuck`/`rework`; and a forgotten `in-progress` stamp yields a silent `queued → pr-open` skip (batch-work's own flow notes the "abandoned-ticket blind spot", `skills/batch-work/references/flow.md`).

### F3 — Prose-only rule inventory (P0–P2)

Rules that exist only as documentation, verified absent from code: CI gate (`alignment-check.sh` never runs `gh pr checks` — 0 hits; "never merge blind on mergeable" is operator discipline, `skills/finish-work/references/flow.md:247`); fallback caps (`fix_cycles > 2` is warn-only in the validator; `## Attempts` articulable-difference unchecked; `skills/_lattice-lib/references/fallback-policy.md`); `--with-review` fix-loop ≤2; `git add -A` ban and post-merge conflict-marker sweep (`flow.md:249-251`); capture/observation duty (`decision-policy.md:22-50`); `profile: strict` asserted in `CLAUDE.md` but never validated against `.lattice/config.yaml`.

### F4 — Binder schema gaps (P1)

Verified against `skills/create-tickets/references/templates/ticket-binder.md` and 85 binders: (a) **no `created`/`updated` fields** — specs and reviews carry both; the only temporal data on a ticket is the `## Finish` ledger, so time-in-state is uncomputable for in-flight tickets, contradicting spc-42's "time-in-state the `status` field yields for free"; (b) `fix_cycles` is declared in the template but **no core-loop script writes it** (only template + validator mention it) — a pure six-skill loop leaves it 0 forever; (c) PR linkage is recorded in three places (binder `prs` row, Spec `prs:` front matter, GitHub `Fixes`/`Refs`) with zero cross-consistency checks; (d) the status vocabulary is copied four times (`reconcile-state.sh:303`, `validate-lattice-artifacts.py:54`, `finish-ledger.sh:496-498`, `workflow-fsm.md`) — drift is a matter of time.

### F5 — FSM design gaps (P1)

`pr-open` has no aging/escalation path — a night-opened PR waits indefinitely if triage is skipped (no counterpart to the in-progress watchdog). The `rework` loop depends on optional review-delivery; without `--with-review` nobody stamps `rework` or `fix_cycles` (F4b confirms). The `fix_cycles ≤ 2` cap has no defined cap-exit transition (compare: fallback bounds have `→ stuck`). `deferred`/`stuck`/`parked` have trip-time stamping (good, tkt-136/137) but no water-level surfacing — morning-triage itself warns "an unreviewed deferred pile is an invisible queue", as a *don't*, not a mechanism. Spec supersede propagates at land-time (finish-work drift check) rather than trip-time — the exact lesson tkt-136/137 learned for fuse-halts, not generalized. The FSM diagram models only one entry edge (PM requirement); `spawn_*` review outcomes, verify-features bug tickets, and the S-class fast path are real entries that the diagram omits.

### F6 — Smaller verified items (P2)

`reconcile-state.sh:588-591` comment claims `has_finish_ledger`/`finish_ledger_merged` are "never used in drift detection" while `:592-604` uses them for `merged_pr_missing_finish_ledger` (stale pre-tkt-179 comment). Skills cite monorepo `docs/` (workflow-fsm.md, morning-triage.md, getting-started.md) as authoritative while asserting "do not require monorepo docs/ to run" — the FSM prose is unresolvable in a vendored install. ID allocation (`spc` local claim, `rev` same-second, ADR `max+1`) is documented as multi-clone-unsafe but unguarded. `found_by`/`escaped_from` are not schema-enforced on bug binders — the escaped-defect metric can silently under-count. `worktree_bind` is honored by batch-work but not by start-work's default call. `alignment-check.sh` treats `mergeable=UNKNOWN` as WARN while `update-pr-base.sh` is fail-closed for the same transient state.

### F7 — Dogfood environment drift (P2, meta)

The installed skill tree (`~/.claude/skills/`) is stale relative to this repo: its `ensure-lattice.sh` is a 62-line skeleton that exits 2 silently on this repo, while the repo's is 224 lines with skeleton checks. Skills invoked globally ran old logic; this very session had to fall back to repo scripts. A refresh/version-check path is needed for dogfooding.

### Confirmed strengths (kept deliberately)

Attention-contract whitelist (six human-owned transitions, closed list) — correct and rare. Trip-time stamping principle (tkt-132/136/137). `reconcile-state.sh` fails closed on unknown — never false-clean. The fail-open/fail-closed posture table is coherent everywhere *except* the marker gate (F1). The `needs_decision` triage queue (`.lattice/reviews/needs-decision.md`) is a closed loop with observed instances. `ratify.sh` single-commit journal+flip with an honest crash-window note. Validator coupled-field rules (`stuck`/`deferred` × `wait_reason`, tkt-151) are exactly the right kind of mechanical check.

## Options

- **A — Maximal hard enforcement** (script everything, no escapes). Rejected: undecidable rules enforced mechanically produce Goodhart compliance (agents satisfy the checker, not the goal); legitimate corner cases (e.g. an infra-class CI outage) become hard walls; brittle under its own false positives.
- **B — Advisory-only** (the original Lattice posture, to protect creativity). Rejected: advisory failures are *silent* (the agent does not know it skipped a step); compliance degrades with context length, concurrent instruction count, and task pressure; multi-agent night fan-out multiplies violation expectation linearly. The observed repeated basic-discipline violations are this option's signature.
- **C — Transitions vs deliberation, with human-adjudicated exceptions** (chosen). Hard-enforce state transitions that are mechanically decidable and high-cost-if-wrong; keep deliberation free; compile decidable corner cases into the rules themselves; route genuine exceptions to human double-confirm with pending as an acceptable outcome; measure escapes as the boundary sensor. Promoted to ADR-007.

## Decision

Adopt Option C and promote it to **ADR-007** (the durable law). Spawn **spc-186** to close the enforcement gap set: machine-enforce the batch merge gate (F1); single-source the status vocabulary and guard `stamp-pr-open` side-state overwrites (F2/F4d); trip-time Spec-supersede sweep (F5); binder timestamps + staleness surfacing (F4a/F5); `fix_cycles` ownership + cap-exit + CI gate with compiled infra-class waiver (F3/F4b); docs repair batch (F6). Defer the full FSM-transition-table-as-data validator to a follow-up spec — it is large enough to deserve its own acceptance criteria.

## Risks

Over-scripting adds friction per rule — mitigated by the five-piece contract (every hard rule ships check/message/escape/trace/metric) and by the decidability prerequisite. False-positive hooks teach circumvention — mitigated by compiling corner cases into rules (class-1) instead of forcing escapes. Human double-confirm adds latency, especially at night — accepted by the operator as a deliberate production compromise (`parked`/`stuck` are first-class states; morning triage is the adjudication venue). Escape metrics could be gamed — low risk while morning triage reviews the escape log.

## Follow-ups

- ADR-007 — hard-limit scope law (this review's Option C, promoted).
- spc-186 — hard-limit enforcement closure (delivery contract, tickets split from it).
- Follow-up spec candidate — FSM transition table as data (single machine-readable source consumed by docs, validator, and a transition guard).
- Follow-up ticket candidate — installed-skill refresh/version-check for dogfood environments (F7).

## Evidence

Directly verified this session (grep/sed against this checkout): `plugins/lattice/hooks/lib/intercept-gh-pr-common.sh:39`; `skills/finish-work/scripts/check-pr-context.sh:44`; `skills/finish-work/SKILL.md:60,83,105,106`; `skills/finish-work/scripts/cleanup-workspace.sh` (zero marker references); `skills/_lattice-lib/scripts/stamp-pr-open.sh:346-347`; `skills/finish-work/scripts/alignment-check.sh` (0 hits for `gh pr checks`); `skills/create-tickets/references/templates/ticket-binder.md` (no `created`/`updated`); `skills/_lattice-lib/scripts/reconcile-state.sh:303,588-604`; `tools/validate-lattice-artifacts.py:54-58`; `skills/_lattice-lib/scripts/finish-ledger.sh:496-498`; `skills/batch-work/` (no scripts dir). Exploration passes covered the six delivery-loop skills, `_lattice-lib` scripts + plugin hooks + bats suites, and the `.lattice` data model (85 binders, 6 specs, 15 reviews). Source docs: `docs/workflow-fsm.md`, `docs/day-phase.md`, `docs/morning-triage.md`, `docs/adr/README.md`, `CLAUDE.md`. Amendments cited: tkt-90 (validator scope honesty), tkt-132/136/137 (trip-time stamping), tkt-179 A8 (reconcile drift class).

## Log

- 2026-08-29 — opened (whole-workflow audit request) → concluded (outcome: spawn_spec → spc-186; law promoted to ADR-007). Evidence verified first-hand against this checkout; operator confirmed the boundary law with one amendment — red-line exception adjudication is always human (double-confirm), pending acceptable, no agent self-adjudication of red lines.
