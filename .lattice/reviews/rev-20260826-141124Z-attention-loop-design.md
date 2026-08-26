---
id: rev-20260826-141124Z
slug: attention-loop-design
title: Attention loop — closing the human-standby gap in the day/night delivery cycle
kind: design
status: concluded
outcome: spawn_spec
summary: "3-round design dialogue distilled: attention contract, decision policy, preferences, fallback, chain review; FSM audit found 9 gaps"
created: 2026-08-26
updated: 2026-08-26
related_specs: [spc-42]
related_tickets: []
related_prs: []
---

# Review: Attention loop — closing the human-standby gap

> **TL;DR:** A three-round architecture dialogue mapped the team's ideal day/night delivery cycle onto Lattice, found that human attention is not yet modeled as a first-class resource, designed five coupled mechanisms (decision policy, team preferences, bounded fallback, chain review, day-phase recipe), and closed with a formal state-machine audit that surfaced 9 concrete gaps. All deliverables are locked in `spc-42`.
> **Kind:** design · **Status:** concluded · **Outcome:** spawn_spec
> **Next:** create-tickets under spc-42 (ADR-004 records the cross-feature law)

## Context

The team's target operating model is a **day/night cycle**:

- **Day (attended):** a PM brings a business requirement; engineers + AI translate it into technical requirements, architecture options, then Spec/ADR/tickets. Human participation here is *deliberate and high-value* — the human must ratify the macro direction.
- **Night (unattended):** agents batch-execute the day's tickets on sibling worktrees (batch-work). No merges at night.
- **Morning (triage):** an independent review agent has already reviewed the delivered chain; the human reads a ranked digest, ratifies queued decisions, deep-reviews only severe findings, and merges. The team already trusts AI review enough that clean verdicts pass without deep human review.

The declared pain: agents demanding mid-execution confirmations (or failing closed unattended), taste questions blocking nights, unbounded retry burn, and no reviewer that sees the *whole chain* (requirement → Spec/ADR → tickets → code) rather than one diff. This Review distills the design dialogue (2026-08-26) into durable findings. The dialogue itself followed the pattern it recommends: evidence-first repo audit by the AI, narrative pain/vision input from the human, gap analysis and prioritized proposals per round, human selecting among recommendations.

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | Real and verified. review-code / review-production / finish-work mini-review are all diff- or PR-scoped; `alignment-check.sh` is checkbox-level, not semantic. batch-work ends at "human reviews N PRs" with no digest. No decision policy, no preference store, no fallback bounds exist anywhere in `skills/` or `_lattice-lib/`. |
| Information | Sufficient — full skill tree read (13 skills, `_lattice-lib` references, dogfood `.lattice/` state); team's operating model described first-hand across three rounds. |
| Hidden issues | (1) Dogfood drift found in this repo: spc-12 A1–A4 unchecked with empty `prs:` while all four features shipped via `dev → main` merge — the dev→main integration path bypasses finish-work's ledger/alignment; the rework/amendment gaps found below are the same class of problem. (2) `tkt-35` ID collision (two binders share the id) — validators lack a duplicate-id check. Both are evidence for the FSM/observability findings, not separate scope here. |

## Findings

### 1. Human attention is not modeled; the expensive gates are unowned

The lifecycle enumerates *process* gates but not *attention* gates. Dry-running the full cycle, humans are forced synchronous at: PCA confirm (worth it), ticket meta batch (worth it), mid-EXECUTE new principals (fail-closed unattended), CI babysitting (pure standby), N-PR review after batch (the bottleneck batch-work moves but does not remove), and merge ceremony. **Fix:** define an explicit *attention contract* — a white-list of human-owned transitions (macro sign-off, decision ratification, deep-review verdict, Spec revision, cancel, merge) with every other transition delegable under policy. ADR-004 §1.

### 2. Day phase: front-load the night's questions

Three mechanisms move unknown night-time questions into the cheap attended window:

- **Solution proposal as a formal rev kind** — AI runs a codebase reality pass, presents 2–3 candidate architectures (touch-set, risks, reversibility, trade-offs) with one recommendation; the human answers a multiple-choice question, not an essay question. The proposal must state what it considered and rejected (coverage attestation).
- **Anticipated-decisions scan at create-tickets** — per ticket, the agent mentally dry-runs the implementation against real code and lists the decision points it expects (error semantics, naming, library choice…). Each gets a disposition: `pre-resolved` (batch-confirm now) / `agent-decides+journal` / `must-ask`.
- **`## Approach` in the binder** — 5–10 lines of planned implementation sketch + touch-set written at split time, when the planner has global context and the human is present. Path divergence at night comes from missing shared priors, not agent weakness.

### 3. Mid-EXECUTE churn: enumerate decision *classes*, not decision instances

Exhaustive up-front enumeration of questions is impossible; a **total transition function over decision classes** is not. `decision-policy.md` (new `_lattice-lib` reference) defines:

- **Resolution chain** (first hit wins): ticket AC / binder Approach → Spec Decisions → ADR → `.lattice/preferences.md` → default heuristics (match codebase convention > minimize public surface > pick the most reversible option) → park & pivot.
- **Reversibility × blast-radius matrix:** reversible + ticket-local → agent decides, journals it; irreversible OR cross-contract → attended: PCA batch; unattended: **park & pivot** — record in `## Pending decisions`, implement to the boundary behind the most reversible seam, mark PR `needs-decision`, continue other tickets. A night is never lost to one question.

### 4. Team preferences: transparent, versioned, self-growing memory

`.lattice/preferences.md` — committed Markdown, no DB, no vector store (matches the "transparent memory" philosophy). Entries carry constraint-language severities (INVARIANT / DEFAULT / HINT) so taste (HINT: "tech-blue theme") never blocks a night while hard constraints (INVARIANT: "Supabase — enterprise contract") still park. Growth loop: a decision-journal entry ratified twice → promotion proposal in the morning digest → one-click accept into preferences. Preferences are superseded with a date, never deleted; Spec/ADR always outrank preferences; every use is cited in the journal.

### 5. Unattended fallback: stop-with-ledger is a success, not a failure

`fallback-policy.md` (new `_lattice-lib` reference), injected into batch-work spawn briefs:

- **Pivot over retry:** before any retry the agent must write to `## Attempts` what it believes failed and what will differ — no articulable difference, no retry. ≤2 tries per path, ≤2–3 paths per ticket.
- **Early-stop signals:** same error twice (no new information) → stop; fix requires touching files outside ticket `paths` (scope escape) → stop — that is a planning defect, not an execution problem.
- **Budgets:** per-ticket wall-clock timebox + attempt caps (config-tunable).
- **Batch fuse:** > threshold of a layer failed/stuck → halt subsequent layers (systemic failure: broken base/env), graceful-drain running agents.
- A `stuck` ticket with a complete Attempts ledger + one well-formed question is a *deliverable*: the morning human starts from a map of dead ends, not from zero.

### 6. Chain review: the missing skill, and why Lattice is pre-adapted to host it

No existing skill reviews the delivered chain (Spec A* ↔ tickets ↔ merged code, cross-PR coherence). New skill **`review-delivery`**:

- **Context assembly is mechanical because the bloodline is the manifest:** `build-review-context.sh` collects, for spc-N, the Spec + cited ADRs + binders (journals, attempts, repro evidence) + PR bodies/diffs + batch report + test evidence.
- **Independence law:** the reviewer consumes durable artifacts ONLY — never implementer transcripts (avoids anchoring; this is the payoff of the "self-contained artifacts" invariant). If the chain cannot be understood from artifacts alone, that is itself a finding. Cross-model review when available.
- **Four axes:** requirement fidelity (semantic A*→evidence RTM, orphan criteria, ticket-less code); cross-PR coherence (interface fit, duplicated/conflicting solutions, pre-merge integration build on a throwaway branch in DAG order); decision-ratification queue; per-PR findings (reuse review-code contract).
- **Output:** morning digest — every PR triaged `auto-pass | ratify-then-pass | deep-review`, ranked, with recommended merge order and preference-promotion proposals.
- **Overnight fix loop:** material findings dispatch bounded (≤2 cycles) implementer-fix → re-review before morning.
- **Trust calibration** (the team auto-passes clean verdicts, so false negatives are the costly error): per-axis attestation instead of bare LGTM; periodic human sampling of "clean" PRs; escaped-defect metric via lineage (bug tickets trace back to the PR that introduced them).

### 7. State-machine audit: 9 gaps, almost all cross-machine edges

Formalizing the workflow as three coupled machines — M1 planning (S0 requirement → S6 tickets), M2 execution per ticket (E0 queued … H4 merged), M3 knowledge (journal → preference/ADR) — and checking completeness, liveness, safety, and observability:

- **Missing exits (dead ends):** `parked` has no wake-up (ratify must atomically write the decision and re-queue); `stuck` needs three enumerated exits (unblock→re-queue / re-scope→M1 / cancel); rejected-PR has no `rework` state (findings become the new brief, ticket re-enters the queue — the address-review shape); fix-cycle exhaustion must escalate to deep-review explicitly.
- **Missing cross-machine edges:** execution-discovered **Spec revision** (E3→S4; distinct from finish-work's land-time drift — currently no owner); `NOTICED BUT NOT TOUCHING` items must flow into the digest (E1→S6) or they evaporate overnight; **rebase-invalidated verdicts** (H4→R1: a materially changed rebase voids the review verdict; clean rebase carries it).
- **Missing slow-variable transition:** preference supersede (fixed in Finding 4).
- **Safety invariants to codify:** night states can never reach Merged (exists — marker); transitions fire only on durable artifacts; every decision transition journaled; human-owned transitions white-listed (= the attention contract); **every autonomous loop declares an upper bound** (all current loops comply: PCA ≤5, repro ≤2, fix ≤2, retry ≤2×path — make it law).
- **Observability:** ticket state is currently smeared across issue state, PR existence, markers, worktrees, and binder prose. Extend the existing binder field-table **`status`** into an FSM enum (working: queued / in-progress / parked / stuck / pr-open / rework / deferred; terminal: `closed`, staying compatible with finish-ledger's existing stamp — merged vs closed-without-merge is read from the `## Finish` ledger's `mergedAt`): validators can reject illegal transitions, the digest becomes a fold over binder states, and time-in-state falls out as the first DORA-lite metric for free.

## Recommendations

1. Lock `spc-42` with the acceptance criteria below (done same-pass) and record the cross-feature law as ADR-004 (attention contract; decision resolution chain; artifact-only reviewer independence; bounded-loop invariant; binder status as state SoT).
2. Ticket priority: decision-policy + fallback-policy + binder/template extensions (unblocks nights) → review-delivery + context bundle + digest (unblocks mornings) → batch-work upgrades (fuse, watchdog, --with-review) → rework/rebase re-entry edges → day-phase recipe + preferences scaffolding.
3. Explicitly deferred: risk-tiered auto-merge (team keeps human-always-merge for now; marker gate unchanged), tracker adapters beyond GitHub, full metrics tooling beyond the free time-in-state field.
4. Separately file the dogfood hygiene items observed during audit (dev→main bypass of finish-ledger; duplicate-id validation) — evidence in Problem Audit; not part of spc-42 scope.

## Outcome (required to conclude)

| outcome | When |
| --- | --- |
| `spawn_spec` | Need a locked Spec before tickets ✓ |

**Outcome:** `spawn_spec` — `spc-42` locked same-pass in this worktree; ADR-004 co-created.

### Follow-ups

- [x] Spec `spc-42` — `.lattice/specs/spc-42-attention-loop.md` (same-pass)
- [x] ADR-004 — `docs/adr/004-attention-contract-and-night-shift-delivery.md` (same-pass)
- [ ] Tickets — via create-tickets under spc-42 (next)
- [ ] Dogfood hygiene issues (dev→main ledger bypass; duplicate binder id check) — file separately, not under spc-42

## References

- Skills audited: `skills/` (all 13 SKILL.md + `_lattice-lib/references/` definition-of-done, orchestration-patterns, constraint-language)
- Dogfood evidence: `.lattice/specs/spc-12-skill-gap-bridge.md` (unchecked A1–A4, empty prs), `.lattice/tickets/tkt-35-*` (id collision)
- Prior review: `rev-20260825-072540Z` (ERP cross-compare — batch-work lineage)
- ADR: `ADR-002` (GitHub-native / ego-browser / sibling-worktree strategy this design extends)

## Links

Bare ids in front matter lists only — `spc-42` linked.
