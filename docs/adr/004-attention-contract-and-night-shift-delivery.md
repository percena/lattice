# ADR 004: Attention contract and night-shift delivery laws

- **Status:** Accepted
- **Date:** 2026-08-26
- **Deciders:** maintainers
- **Related:** `spc-42`, `rev-20260826-141124Z`
- **Related ADRs:** `ADR-002` (GitHub-native / sibling-worktree strategy this extends)

## Context

Lattice constrains the delivery *path* (Spec → ticket → worktree → PR → merge) but has no law for the delivery *schedule* teams actually run: attended planning by day, unattended batch execution by night, review-gated merges by morning. Unattended operation surfaces forces the original design never had to resolve: who may decide what while no human is present, where taste/stack defaults come from, when an agent must stop trying, what an independent reviewer may read, and where a ticket's state authoritatively lives. A formal state-machine audit (`rev-20260826-141124Z`, Finding 7) showed the missing pieces are systemic (cross-machine edges and invariants), so they belong in durable law, not in individual skill prose.

## Decision Drivers

- Human attention is the scarcest resource in the cycle; it must be spent only where it is irreplaceable
- Unattended runs must never block on a question, and never burn a night on a dead end
- Review verdicts are trusted enough to auto-pass, so reviewer independence and calibration are safety-critical
- Everything must stay grep-able, versioned, and agent-portable (no runtime services, no black-box memory)

## Considered Options

- **Attention: enumerate human gates vs. leave to skill prose** — chosen: closed white-list (auditable, config-addressable); prose scatters and drifts.
- **Preferences: versioned Markdown vs. DB/vector memory** — chosen: Markdown with constraint-language severities; black-box memory contradicts the transparent-memory philosophy and is not reviewable by the team.
- **Reviewer context: artifact-only vs. include implementer transcripts** — chosen: artifact-only; transcripts anchor the reviewer to the implementer's reasoning and void third-party value. Corollary: artifact insufficiency is itself a finding.
- **Fallback: policy reference + validators vs. guard.sh-style hard wrapper** — chosen: policy + validators (Lattice is discipline-first, not enforcement-heavy; ADR-002 already rejected guard.sh ports).
- **Merge autonomy: risk-tiered auto-merge vs. human-always-merge** — chosen: human-always-merge for now; revisit only after the escaped-defect metric exists and earns trust.

## Decision

We will govern unattended delivery with six laws:

1. **Attention contract.** Human-owned transitions form a closed white-list: macro sign-off, decision ratification, deep-review verdict, Spec revision, cancel, merge. Every other transition is delegable under policy. Nights never merge (the batch marker gate is unchanged).
2. **Decision resolution is a total function.** Every mid-execution decision resolves through: ticket AC/binder Approach → Spec Decisions → ADR → `.lattice/preferences.md` → default heuristics (codebase convention > minimal public surface > most reversible) → park & pivot. Reversible + ticket-local decisions are self-decided and journaled; irreversible or cross-contract decisions are PCA-batched when attended and parked-with-pivot when not. An unattended agent never blocks on a decision.
3. **Team preferences are transparent versioned Markdown** (`.lattice/preferences.md`), severity-labeled with the existing constraint language (INVARIANT parks, DEFAULT journals, HINT just applies). Entries are promoted from twice-ratified decision-journal items, superseded with a date rather than deleted, and always outranked by Spec/ADR.
4. **Chain-review independence is artifact-only.** The delivery reviewer consumes durable artifacts (Spec, ADRs, binders, PR bodies/diffs, evidence) and never implementer transcripts. Verdicts require per-axis attestation; a materially changed rebase voids a verdict; trust is calibrated by periodic human sampling of clean PRs and an escaped-defect metric traced through lineage.
5. **All autonomous loops are bounded, and stop-with-ledger is success.** Every loop declares an upper bound (retry ≤2/path, paths ≤3/ticket, fix-cycles ≤2, plus timeboxes); retries require an articulated difference; repeated errors and scope escape stop the ticket; a layer-level fuse halts systemically failing batches. A stuck ticket with a complete Attempts ledger and one well-formed question is a first-class deliverable.
6. **The binder field-table `status` is the single source of truth for ticket state**, extended in place: working states queued / in-progress / parked / stuck / pr-open / rework / deferred; terminal `closed` (merged vs closed-without-merge distinguished by the `## Finish` ledger's `mergedAt`, which finish-ledger.sh already stamps); legacy `open` accepted as a coarse value during lazy migration. Orchestrators, digests, validators, and metrics read and write this field; state is never inferred from PR, marker, or worktree existence alone, and validators reject illegal transitions.

## Consequences

- **Positive:** unattended nights become lossless (questions, dead ends, and noticed items all land as morning artifacts); morning triage collapses to a digest fold over binder states; reviewer trust becomes measurable instead of vibes; the self-contained-artifact invariant finally pays its full dividend.
- **Negative / trade-offs:** more binder structure to maintain (mitigated by templates + lazy migration); artifact-only review can miss context a transcript held (accepted — that gap is reported as a documentation finding); policy-not-enforcement means a non-compliant agent can still misbehave (consistent with Lattice's discipline-first stance).
- **Follow-ups:** delivery breakdown in `spc-42`; dogfood hygiene (dev→main ledger bypass, duplicate binder ids) filed separately.
- **Verification:** `validate-lattice-artifacts.py` status/transition checks; batch-work spawn briefs cite decision/fallback policies; review-delivery digests carry attestation blocks.

## Status history

- 2026-08-26: Proposed → Accepted

## Notes

Rejected alternatives and the full audit live in `rev-20260826-141124Z` (`.lattice/reviews/rev-20260826-141124Z-attention-loop-design.md`).

## Amendment (2026-08-27, tkt-90)

§6's closing claim ("validators reject illegal transitions") overstated the shipped check: `validate-lattice-artifacts.py` validates state **snapshots**, not transition history — unknown status values, `closed` without a Finish ledger, a merged Finish ledger without terminal status (`finish_without_terminal_status`, added by tkt-90 after 19 binders stranded at `pr-open` went undetected), and duplicate ticket ids (`duplicate_ticket_id`). Edge legality between two valid snapshots is owned by the skills that perform the transitions (`docs/workflow-fsm.md` §5). §3's promotion path also gained a direct edge after acceptance: an explicit operator-stated preference is written at utterance time by the active skill (Capture duty, `decision-policy.md`, pr-88) — the ×2 promotion remains the path for journal-derived candidates.

## Amendment (2026-08-27, tkt-136)

Two design-level FSM gaps from `rev-20260827-064527Z` (reaffirmed `rev-20260827-102420Z` F7) resolved with operator-chosen options:

- **FSM-2 (fuse-halt / blocked-by-failure SoT honesty) — Option B chosen.** Fuse-halt and blocked-by-failure currently leave the binder `queued` (report-level only); the SoT says "schedulable" and the real state is "not schedulable." Option B: batch-work stamps `deferred` + a reason (`fuse-halt` | `blocked-by-failure`) at trip time so the binder reflects "not schedulable." The binder enum stays unchanged — `deferred` already exists; `deferred → queued` remains a human transition (re-schedule into a later batch). The agent stamps the initial `deferred` at trip time, narrowing the SoT-honesty window. Pairs with FSM-2b (tkt-132: watchdog-timeout stamps `stuck`). Implementation: `tkt-137`.

- **FSM-4 (`parked → queued` atomicity) — Option A chosen.** `start-work:89` claims ratification "atomically writes the decision into `## Decision journal` **and** flips `parked → queued` (one write — never a re-queued binder without its recorded decision)." But a Markdown file edit is not atomic; a crash between the two writes yields the "never" state. Option A: a new `ratify.sh` script (`_lattice-lib/scripts/`) writes both edits in one git commit, narrowing the crash window to a single reviewable commit. The "atomically...one write — never" claim in `start-work:89` and `workflow-fsm.md` §2 is updated to "single-commit (reviewable pair); crash window narrowed, not eliminated." Implementation: `tkt-138`.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-004` or this path._
