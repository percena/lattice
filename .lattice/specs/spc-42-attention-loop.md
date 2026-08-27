---
id: spc-42
slug: attention-loop
title: Attention loop — unattended night-shift delivery with a modeled human-attention contract
kind: feat
status: done
mode: C
priority: P2
summary: "Decision policy, team preferences, bounded fallback, chain review (review-delivery), FSM status field: close the day/night cycle"
created: 2026-08-26
updated: 2026-08-26
tickets: [tkt-43, tkt-44, tkt-45, tkt-46, tkt-47, tkt-48, tkt-49, tkt-50]
prs: [pr-52, pr-53, pr-54, pr-55, pr-56, pr-57, pr-58, pr-59]
reviews: [rev-20260826-141124Z]
supersedes: []
superseded_by: null
---

# Spec: Attention loop — unattended night-shift delivery

> **TL;DR:** Make human attention a modeled resource: day-phase mechanisms front-load the night's questions, a decision policy + team preferences + bounded fallback let agents run unattended without blocking or spinning, a new `review-delivery` skill reviews the delivered chain from artifacts alone and emits a morning digest, and a binder `status:` FSM field makes ticket state observable and checkable. Merge authority stays human (batch marker unchanged).
> **Kind:** feat · **Status:** done · **Mode:** C · **Priority:** P2
> **Path:** spc-42 → tkt-… → pr-…

## Why

Teams running Lattice in a day/night cycle (attended planning by day, unattended batch delivery by night, review-gated merges by morning) lose the night's leverage to four failure shapes: agents blocking (or failing closed) on mid-execution decisions, taste/stack questions with no lookup source, unbounded retries on dead-end paths, and no reviewer that sees the delivered *chain* (Spec A* ↔ tickets ↔ code, cross-PR coherence) — so the morning human re-derives context PR by PR. A state-machine audit of the full workflow (`rev-20260826-141124Z`, Finding 7) additionally found 9 formal gaps: missing exits (parked wake-up, stuck triage, rework, fix-cycle escalation), missing cross-machine edges (execution-discovered Spec revision, noticed-items capture, rebase-invalidated verdicts), preference supersede, and no single source of truth for ticket state.

## In scope

- `_lattice-lib/references/decision-policy.md` — decision resolution chain, reversibility × blast-radius matrix, park & pivot, journal contract
- `_lattice-lib/references/fallback-policy.md` — pivot-over-retry, early-stop signals, budgets, batch fuse, Attempts ledger
- `.lattice/preferences.md` mechanism — severity-labeled team preferences, promotion + supersede lifecycle, ensure-lattice scaffolding
- Ticket binder template extensions + frontmatter `status:` FSM field + validator transition checks
- `create-tickets` additions — anticipated-decisions scan, `## Approach` authoring at split time
- `review-delivery` skill + `_lattice-lib/scripts/build-review-context.sh` — chain review, morning digest, attestation
- `batch-work` upgrades — decision/fallback protocol in spawn briefs, watchdog/timebox, batch fuse + graceful drain, evidence contract, `--with-review`
- Rework + re-entry edges — returned-PR rework loop; rebase-invalidated verdict rule in finish-work; parked-ticket wake-up on ratify
- Day-phase recipe + workflow FSM reference docs

## Out of scope

- Risk-tiered auto-merge (team keeps human-always-merge; batch marker gate unchanged) — revisit only after escaped-defect metric exists and is trusted
- Tracker adapters beyond GitHub (Jira/Linear)
- Cross-repo (multi-repo) feature orchestration
- Full metrics/DORA tooling beyond the time-in-state data the `status:` field yields for free
- Dogfood hygiene fixes observed during the audit (dev→main finish-ledger bypass; duplicate binder id validation) — file as separate tickets outside this Spec
- Porting any ERP guard.sh-style hard enforcement; policies stay references + validators, not wrappers

## Acceptance

- [x] **A1** `_lattice-lib/references/decision-policy.md` exists and defines: (a) the resolution chain — ticket AC/binder Approach → Spec Decisions → ADR → `.lattice/preferences.md` → default heuristics (codebase convention > minimal public surface > most reversible) → park & pivot; (b) the reversibility × blast-radius matrix (reversible+local → self-decide + journal; irreversible or cross-contract → attended PCA / unattended park & pivot); (c) the journal contract (every self-decision cites its resolution source). start-work and batch-work reference it.
- [x] **A2** `_lattice-lib/references/fallback-policy.md` exists and defines: pivot-over-retry with the articulated-difference rule (no retry without a written cause + delta in `## Attempts`), caps (≤2 tries/path, ≤3 paths/ticket, per-ticket timebox), early-stop signals (same error twice; scope escape beyond ticket `paths`), the batch fuse (layer failure ratio > threshold → halt subsequent layers, graceful-drain running agents), and the stuck-with-ledger framing (Attempts ledger + one well-formed question = deliverable). batch-work injects it into spawn briefs.
- [x] **A3** `.lattice/preferences.md` is scaffolded by `ensure-lattice.sh` (template with INVARIANT/DEFAULT/HINT sections per `constraint-language.md`); decision-policy resolution consults it; a decision-journal entry ratified twice generates a promotion proposal in the morning digest; entries are superseded with a date, never deleted; Spec/ADR outrank preferences.
- [x] **A4** The ticket-binder template gains `## Approach`, `## Anticipated decisions` (each item dispositioned `pre-resolved | agent-decides | must-ask`), `## Decision journal`, `## Pending decisions`, `## Attempts`, and the existing binder field-table `status` is extended into the FSM enum: working states `queued | in-progress | parked | stuck | pr-open | rework | deferred`, terminal `closed` (merged vs closed-without-merge distinguished by the `## Finish` ledger's `mergedAt`, as finish-ledger.sh already stamps), with legacy `open` accepted as a coarse value (lazy migration — validator warns, not fails); `validate-lattice-artifacts.py` rejects unknown status values and illegal transitions (e.g. `closed` without a `## Finish` ledger).
- [x] **A5** `create-tickets` runs an anticipated-decisions scan per proposed ticket (dry-run against real code, emit decision points with dispositions into the binder) and authors `## Approach` (sketch + touch-set) at split time; both land in one delivery-meta batch, not serial questioning.
- [x] **A6** `review-delivery` skill exists: input `spc-N | --ids tkt list | batch report`; assembles context exclusively from durable artifacts via `build-review-context.sh` (Spec, ADRs, binders incl. journals/attempts, PR bodies+diffs, batch report, test evidence — never implementer transcripts); reviews four axes (semantic A*→evidence fidelity incl. orphan criteria and ticket-less code; cross-PR coherence incl. a throwaway pre-merge integration build in DAG order; decision-ratification queue; per-PR findings reusing the review-code contract); emits a morning digest triaging every PR `auto-pass | ratify-then-pass | deep-review` with recommended merge order; per-axis attestation is mandatory (no bare LGTM); never merges.
- [x] **A7** `batch-work` upgrades: spawn briefs carry the decision + fallback protocols and the evidence contract (fresh test output, decision journal, e2e evidence when UI); per-ticket watchdog/timebox marks hung agents `failed`; batch fuse per A2; `--with-review` chains `review-delivery` after the last layer and dispatches a bounded (≤2 cycles) fix loop for material findings before the digest is finalized.
- [x] **A8** Re-entry edges exist: a PR returned with findings moves its binder to `status: rework` with findings as the new brief and re-enters the queue (address-review shape); ratifying a parked decision atomically writes the decision into the binder and flips `parked → queued`; finish-work re-runs its mini-review when a base update materially changes the diff (conflict or non-trivial rebase), carrying clean-rebase verdicts unchanged.
- [x] **A9** Docs: `docs/workflow-fsm.md` records the three coupled machines, the transition table with owners, the human-owned transition white-list (macro sign-off, ratify, deep-review verdict, Spec revision, cancel, merge), and the bounded-loop invariant (every autonomous loop declares an upper bound); `docs/day-phase.md` records the recipe — business requirement → solution-proposal rev (2–3 options + recommendation + rejected-alternatives attestation) → spec → adr → tickets.

## Non-goals

- Will not remove or weaken the batch marker merge gate — nights never merge
- Will not build chat-memory or vector stores — preferences stay grep-able Markdown
- Will not let the review agent read implementer transcripts, ever
- Will not add unbounded loops anywhere — the bounded-loop invariant is law

## Decisions (principal, user-confirmed)

1. **Attention contract** — human-owned transitions are a closed white-list (macro sign-off, decision ratification, deep-review verdict, Spec revision, cancel, merge); everything else is delegable under policy. Merge stays human via the existing batch marker. (ADR-004 §1)
2. **Decision resolution is a total function** — every mid-execution decision resolves through the chain in A1; unattended runs never block on a decision: reversible+local → journal; otherwise park & pivot. (ADR-004 §2)
3. **Preferences are transparent versioned Markdown** — in-repo, severity-labeled, promoted from twice-ratified journal entries, superseded not deleted; outranked by Spec/ADR. No DB/vector store. (ADR-004 §3)
4. **Reviewer independence is artifact-only** — the chain reviewer consumes durable artifacts, never transcripts; verdicts require per-axis attestation; material rebases void verdicts; trust is calibrated by human sampling of clean PRs plus the escaped-defect lineage metric. (ADR-004 §4)
5. **Stop-with-ledger is process success** — bounded attempts with the articulated-difference rule; batch-level fuse; a stuck ticket with a good ledger is a deliverable, and its scope-escape signal routes to Spec/ticket revision, not more retries. (ADR-004 §5)
6. **The binder field-table `status` is the single source of truth for ticket state** — extended in place (compatible with finish-ledger's existing `closed` stamp); orchestrators, digests, validators, and metrics read/write this field; state is never inferred from PR/marker/worktree existence alone. (ADR-004 §6)

## Agent-assumed (secondary)

- Digest lands as a Markdown file under `.lattice/reviews/` (kind: digest) plus stdout; a GH issue-comment mirror can come later
- Fuse threshold default 50% of a layer; timebox defaults per mode (S/M/C) — tunable in `.lattice/config.yaml`
- Existing binders migrate lazily: validator warns (not fails) on missing `status:` until touched

## Risks / open questions

- Overnight fix-loop dispatch mechanics (re-spawning implementer agents post-review) need verification in the target agent runtimes — mitigated by `--with-review` being opt-in and dry-run-able
- Semantic A*→evidence fidelity is judgment work; attestation + human sampling guard against rubber-stamping, but calibration needs the escaped-defect metric to accumulate before auto-pass trust is data-backed
- Pre-merge integration build assumes a cheap throwaway branch build; very slow suites may need a subset profile
- **Amendment (2026-08-27 — spc-104 tkt-107):** the escaped-defect metric mechanics landed — bug binders carry `found_by`/`escaped_from` lineage rows (verify-features tracing) and every digest counts escapes per class (`auto-pass` vs `ratify-then-pass`). The "revisit risk-tiered auto-merge only after escaped-defect metric exists and is trusted" trigger (Out of scope) is now armed; auto-merge itself stays out of scope until escapes accumulate and trust is data-backed

## References

- Review: `rev-20260826-141124Z` → `.lattice/reviews/rev-20260826-141124Z-attention-loop-design.md`
- ADR: `ADR-004` → `docs/adr/004-attention-contract-and-night-shift-delivery.md`
- Prior: `spc-12` (skill-gap bridge — batch-work/repro-loop lineage), `ADR-002`
- Existing law this extends: `_lattice-lib/references/definition-of-done.md`, `orchestration-patterns.md`, `constraint-language.md`

## Links / bloodline (L0)

- Tickets: tkt-43 (A1,A2 · G1), tkt-44 (A4 · G1), tkt-45 (A9 · G1), tkt-46 (A3 · G2, blocked_by 43), tkt-47 (A6+A3 · G2, blocked_by 44), tkt-48 (A5 · G2, blocked_by 44), tkt-49 (A8 · G2, blocked_by 43,44), tkt-50 (A7+A2 · G3, blocked_by 43,47)
- Ship plan: multi-PR — one worktree/PR per ticket; layers G1 → G2 → G3 (batch-work compatible)
- PRs: pr-52…pr-59 (all merged to dev 2026-08-26)
- Reviews: `rev-20260826-141124Z`
