---
id: rev-20260827-102420Z
slug: fsm-process-completeness-audit
title: "Lattice FSM & process-completeness audit — in-progress recovery gap, train-retirement doc residue, inform_only no forcing function, morning-triage recipe absent"
kind: audit
status: concluded
outcome: spawn_tickets
summary: "State-machine + process audit of dev (workflow-fsm.md, ADR-004/005, nine lifecycle skills, validator, FSM-related binders). Seven findings: one new FSM SoT-honesty gap (FSM-2b, watchdog-timeout strands tickets in-progress), train-retirement doc residue in finish-work SKILL.md, inform_only outcome has no forcing function, no morning-triage recipe, FSM M1 row missing Spec done, diagram/table inconsistency, FSM-2/FSM-4 still undecided."
created: 2026-08-27
updated: 2026-08-27
related_specs: [spc-42]
related_tickets: [tkt-49, tkt-90, tkt-118, tkt-123]
related_prs: []
---

# Review: Lattice FSM & process-completeness audit

> **TL;DR:** A state-machine + process-completeness audit of the dev tip surfaced seven findings. One is a **new FSM SoT-honesty gap** (FSM-2b) the prior `rev-20260827-064527Z-fsm-design-gaps` audit missed: watchdog-timeout/crash of an already-spawned ticket leaves its binder at `in-progress` while the batch report says `failed` — the SoT says "active" and the real state is "abandoned." Four are doc/process gaps (train-retirement residue in `finish-work/SKILL.md`, `inform_only` has no forcing function, no morning-triage recipe, FSM M1 row missing Spec `done`). Two are known-undecided (FSM-2/FSM-4, reaffirmed). Three interim conclusions were retracted after cross-checking the skill implementations.

## Method

Read in full: `docs/workflow-fsm.md`, `docs/day-phase.md`, `docs/adr/004`, `docs/adr/005`, `.lattice/specs/spc-116-retire-release-train.md`, nine skill `SKILL.md` files (`_lattice-lib`, `create-spec`, `create-tickets`, `start-work`, `create-pr`, `finish-work`, `review-delivery`, `batch-work`, `create-review`), `tools/validate-lattice-artifacts.py` (check extraction), and binders `tkt-49`, `tkt-90`, `tkt-118`. Greps confirmed every file:line citation below.

## Context

The three coupled machines (`docs/workflow-fsm.md`): **M1** planning (day, attended), **M2** execution (night, per-ticket, unattended), **M3** knowledge (slow). ADR-004 §6 makes the binder field-table `status` the single source of truth for M2 state. tkt-90 (closed, pr-100) tightened the validator to snapshot-check `closed_without_finish` / `finish_without_terminal_status` / `duplicate_ticket_id` and made the "rejects illegal transitions" claim honest (snapshot-only, edge legality owned by skills). tkt-49 (closed, pr-57) added the reentry edges (rework/parked→queued/rebase-re-review/stuck triage). tkt-118 (closed, pr-125) retired the release-train mechanism per ADR-005. This audit cross-checks those closures against the current skill/doc bodies and surfaces what they did not close.

## Problem audit

The question ("are there FSM / process-completeness gaps?") is crisp; info is sufficient (all source files are in-tree and were read directly). One-line skip of the deeper problem-audit recipe — no must-have info is missing.

## Finding 1 — `inform_only` review outcomes have no forcing function (medium)

**Where:** `skills/create-review/SKILL.md:42` (outcome enum), `:103-109` (outcome→next-step table — `inform_only`→"stop"), `:82` (Review-only on base is fine).

**The gap.** `create-review` defines five outcomes: `inform_only | spawn_spec | spawn_tickets | spawn_fix | needs_grill`. `spawn_*` and `needs_grill` route to a next-step skill. `inform_only` is the only one with no handoff — it is terminal ("stop"). `needs_grill` exists but routes specifically to `create-spec` for **fuzzy product-scope** alignment; it does not fit engineering-design policy decisions (e.g. "should the binder enum accept `blocked-by-failure`?"). A review that surfaces a design-level decision but cannot use `spawn_*` (no actionable ticket exists without the decision) and cannot use `needs_grill` (not product scope) falls back to `inform_only` and stops — with **no tracker, no triage queue, no deadline**.

The prior `rev-20260827-064527Z-fsm-design-gaps` is the live example: two design-level gaps (FSM-2, FSM-4) concluded `inform_only` on 2026-08-27 and await a team policy decision with no forcing function. The only closed-loop tracker that exists (`review-delivery`'s escaped-defect metric, `skills/review-delivery/SKILL.md:110`) covers `auto-pass` verdicts only — a different artifact class.

**Severity:** medium. Design decisions stall indefinitely; the SoT (the review file) records the gap but nothing re-surfaces it.

## Finding 2 — FSM-2b: watchdog-timeout/crash strands spawned tickets at `in-progress` (medium, new)

**Where:** `skills/batch-work/SKILL.md:61` (binder status stamped `queued → in-progress → pr-open`), `:93` (stamp `in-progress` on start), `:124` (blocked-by-failure stays `queued`), `:126` (report `agent status: ok/failed/blocked/fuse-halted`), `:136-137` (watchdog marks `failed`, ledger left intact), `:182` ("the timebox *is* the wait. Watchdog marks `failed`, keeps the ledger, moves on"), `:209` (verification: over-timebox tickets `failed` (`timeout`) with binder ledger left intact); `docs/workflow-fsm.md:32-51` (mermaid — no `in-progress → queued` or `in-progress` self-loop), `:96-108` (transition table — no `in-progress → queued` edge); `skills/start-work/SKILL.md:87-90` (resume enumeration covers `rework`/`parked`/`stuck` only — **not** `in-progress`).

**The gap.** `batch-work` explicitly handles two failure classes: never-spawned and fuse-halted tickets stay `queued` (`:61`, `:213`); blocked-by-failure dependents stay `queued` (`:124`). But a **spawned-but-failed/timed-out** ticket — the watchdog marks it `failed` (`timeout`) in the ephemeral report (`:126`, `:182`, `:209`) while its binder `status` stays `in-progress` (the agent stamped `in-progress` on start, `:93`, and nothing flips it back). This is a **new** SoT-honesty gap, distinct from FSM-2 (which covers fuse-halt/blocked-by-failure leaving tickets `queued`): here the binder says "active work" and the real state is "abandoned at timeout."

Consequences (verified against `references/flow.md`):
1. **SoT dishonesty across runs.** The binder says `in-progress` (active); the real state is "abandoned at timeout." The `failed`/`timeout` status lives only in the ephemeral batch report (`flow.md:246` — "report-level, not the binder enum"). A later run has no durable failure signal.
2. **Undefined cross-run re-entry.** `--groups` reads `parallel_group` + `blocked_by` from **all** binders with no status filter (`SKILL.md:70`, `flow.md:30-34` RESOLVE TICKETS). The "host never silently re-runs a failed ticket" rule (`flow.md:256`) is **in-run only** — it relies on the ephemeral report, which does not exist in a new run. So a new `--groups` run would include the `in-progress` binder as a DAG node, but the host has no rule for "what to do with an in-progress binder from a prior failed run" — and the worktree already exists, so `ensure-workspace` behavior is undefined for this case.
3. **Triage blind spot.** Morning triage reading binders sees `in-progress` (looks like active work) — not "needs attention." `start-work` resume on an `in-progress` binder works for a **human-invoked** resume (the agent continues), but no triage path surfaces the "abandoned in-progress" condition, and the FSM documents no `in-progress → queued` (re-queue) edge.

tkt-49 (closed) added the reentry edges for `rework`/`parked`/`stuck`/`rebase` (acceptance A8) but **not** `in-progress` interruption recovery. The prior `rev-20260827-064527Z` Finding 1 (FSM-2) focused on fuse-halt/blocked-by-failure and did not surface the watchdog-timeout case.

**Severity:** medium. Wasted morning (triage doesn't see the stranding) + a ticket that silently drops out of the batch pipeline. No lineage corruption; no wrong merge.

**Why design, not code.** Options (parallel to FSM-2's A/B/C/D):
- Option A: batch-work stamps `stuck` (with `wait_reason: unblock`) on watchdog-timeout at trip time — the binder reflects "needs human," morning triage routes it through the existing `stuck` exits. Reuses the existing enum; no new value. Cost: an agent-originated `stuck` stamp (currently `stuck` is agent-stamped when fallback bounds hit, `:101` — so precedent exists).
- Option B: add `in-progress → queued` (re-queue) as a triage-owned transition and have batch-work stamp it — but `queued` means "schedulable," and an abandoned ticket may not be schedulable without investigation.
- Option C: batch-work stamps `deferred` (with reason `batch-timeout`) at trip time — but `deferred → queued` is human-owned, and this is the agent doing a human stamp (same tension as FSM-2 Option B).

## Finding 3 — `finish-work/SKILL.md` train-retirement doc residue + dangling §3.4 pointer (medium)

**Where:** `skills/finish-work/SKILL.md:23` (load-on-demand row: "`**merge trains (§3.4)**`"), `:65` (finish cycle checklist: "`**Train landing (multi-PR queue):** ... train-transient version reds distinguished from real failures ...`"), `:93` (red-run disposition: "`train version race`"), `:178` (rationalization: "`train-transient version reds`"), `:185` (red flag: "`Train merge on mergeable alone`"), `:208` (verification: "`Train landing: gh pr checks <N> rollup fetched before each train merge`"), `:216` (verification: "`Train landing: post-merge grep ...`").

**Verified against retirement:**
- `docs/adr/005-version-bump-at-release-boundary.md` §2: "Retire the release-train mechanism **in full**."
- `.lattice/specs/spc-116-retire-release-train.md` in-scope item 7: lists **only** `skills/finish-work/references/flow.md` for the §3.4 rewrite — `skills/finish-work/SKILL.md` is **not** in scope.
- `tkt-118` paths: `skills/batch-work/SKILL.md, skills/batch-work/references/flow.md, skills/finish-work/references/flow.md, skills/create-tickets/references/policy.md` — `finish-work/SKILL.md` is **not** in paths.
- tkt-118 acceptance A7 greps for literal `release-train|train_cut|train mode|--no-train|version cut`. A grep for those literals over `finish-work/SKILL.md` returns **zero** matches — the skill uses `Train landing`/`merge trains`/`train-transient` instead, which A7 does not match.
- `skills/finish-work/references/flow.md` §3.4 was rewritten to "**Sequential merge queue** (DEFAULT when landing a queue of PRs)" (grep-confirmed: zero train refs in flow.md) and §3.4.1 "Dev→main release-boundary version-bump check" was added.

**The gap.** Two defects:
1. **Dangling pointer.** `SKILL.md:23` says "`merge trains (§3.4)`" but flow.md §3.4 is now "Sequential merge queue" — the pointer names retired terminology that no longer matches the target section.
2. **Residue.** `SKILL.md:65,93,178,185,208,216` retain `Train landing`/`train-transient version reds` content. `train-transient version reds` specifically references the version-cut false-positives that ADR-005 retired — after retirement, dev landings are lenient and that concept no longer applies.

**Severity:** medium. A reader of the user-facing `finish-work/SKILL.md` gets retired guidance that contradicts ADR-005 and the already-cleaned `flow.md`. The hard merge gate (alignment-check) is unaffected.

## Finding 4 — no morning-triage recipe document (low-medium)

**Where:** `docs/` contains only `adr/`, `day-phase.md`, `getting-started.md`, `github-surface.md`, `workflow-fsm.md`. `docs/day-phase.md` (read in full) covers the **M1 attended planning** recipe only (requirement → dialogue → proposal rev → sign-off → spec → adr → tickets) — it does **not** cover morning triage.

**The gap.** The morning triage procedure — read the `review-delivery` digest → ratify decision-journal entries (M3) → stamp `deferred` on fuse-halted tickets (M2) → disposition `stuck` tickets (`unblock`/`re-scope`/`cancel`) → consume PR verdicts (`auto-pass`/`ratify-then-pass`/`deep-review`) → run `finish-work` per PR — is scattered across `review-delivery`, `start-work:87-90`, `batch-work`, and `finish-work` skill prose. `workflow-fsm.md` §3 lists the human-owned transitions (white-list) but gives no step-by-step recipe. There is no `docs/morning-triage.md`.

**Severity:** low-medium. Correctness is fine (each skill describes its piece); the gap is operational convenience — a new contributor has no single doc to follow.

## Finding 5 — `workflow-fsm.md` M1 row missing Spec terminal state `done` (low)

**Where:** `docs/workflow-fsm.md:12` (M1 states: "requirement → dialogue → proposal rev → sign-off → Spec locked → ADR (conditional) → tickets" — no `done`/`superseded`); `:18-28` (M1 diagram — ends at `tickets`); `skills/finish-work/SKILL.md:70` ("Spec primary: workstream **complete** → closed + Spec `done`"), `:113` (finish-ledger / Spec primary close), `:220` (verification: "Spec primary: if workstream complete → closed"); `.lattice/specs/spc-116-retire-release-train.md` front matter `status: done` (real instance); `:2` comment `# status: draft | locked | done | superseded`.

**The gap.** Spec has a status lifecycle (`draft | locked | done | superseded`) used in practice, but the FSM M1 row stops at `tickets` and never lists `done` (terminal) or `superseded` (revision = new `spc-N` supersedes old, per `create-spec:121`). The "Spec locked → Spec revised" transition appears in the M1 transition table (`:89`) but the revision's **propagation to existing ticket/binders** (which become obsolete, which are re-sliced) is not defined as an edge. `finish-work` catches land-time Spec drift (`:63`, `:171`) but that is a land-time check, not a revision-transition contract.

**Severity:** low. Doc-only; the mechanism exists, the model just omits it.

## Finding 6 — `workflow-fsm.md` diagram/table inconsistency: `any → closed` (low)

**Where:** `docs/workflow-fsm.md:108` (transition table: "`any → closed (without merge)` | **cancel** | human") vs `:49-50` (mermaid: only `pr --> closed: human merge` and `stuck --> closed: cancel`; no generic `any → closed`).

**The gap.** The table allows cancel from any state (`deferred → closed`, `parked → closed`, `rework → closed`); the diagram only shows `stuck → closed` (cancel) and `pr → closed` (merge). A reader of the diagram alone would miss that a `parked` or `deferred` ticket can be cancelled.

**Severity:** low. Doc-only; the table is authoritative.

## Finding 7 — FSM-2 / FSM-4 reaffirmed undecided (medium, known)

**Where:** `skills/batch-work/SKILL.md:61,213` (fuse-halted/never-spawned stay `queued`, "no new enum values" — deliberate); `skills/start-work/SKILL.md:89` ("atomically wrote the decision into `## Decision journal` **and** flipped `parked → queued` (one write — never a re-queued binder without its recorded decision)" — bare claim, no enforcement); `tools/validate-lattice-artifacts.py` (snapshot-only — does not check parked-journal consistency); `rev-20260827-064527Z-fsm-design-gaps.md` (outcome `inform_only`, undecided since 2026-08-27).

**The gap.** Unchanged from the prior audit:
- **FSM-2:** fuse halt / blocked-by-failure is report-level only; binder SoT stays `queued` → unattended re-run re-spawns dead-end tickets.
- **FSM-4:** `parked → queued` "atomic write" is a bare claim; Markdown has no transaction; a crash between the journal write and the status flip yields the exact "never" state; the validator cannot catch it from a snapshot.

Plus the new sibling (Finding 2 / FSM-2b): watchdog-timeout strands tickets at `in-progress`.

**Severity:** medium. Known; awaiting a policy decision (blocked by Finding 1's forcing-function gap).

## Self-corrections (interim → final)

Three interim conclusions were retracted after reading the skill implementations and binders:

| Interim conclusion | Final | Evidence |
| --- | --- | --- |
| "rework fix-cycle ≤2 exhaustion has no defined path" | **Retracted** | `review-delivery:45` (one pass per invocation, no autonomous re-review; `batch-work --with-review` owns the ≤2 cycle) + triage class `deep-review` (`review-delivery:105`) is the exhaustion exit to human reading. Path is defined via verdict, not a binder state. |
| "M1 has no terminal state" | **Retracted** | `finish-work:70,113,220` stamps Spec `done`; `spc-116` front matter `status: done`. Terminal state exists; only the FSM M1 row omits it (Finding 5). |
| "release boundary is not modeled" | **Retracted** | tkt-118 A8 added a `finish-work` dev→main pre-merge version-bump check (`flow.md §3.4.1`, grep-confirmed). ADR-005 §4 landed. |
| "in-progress has no re-entry edge" | **Retained, narrowed** | tkt-49 (closed, pr-57) added rework/parked→queued/rebase/stuck edges (acceptance A8) but **not** `in-progress` interruption recovery. See Finding 2. |
| "review outcome execution is untracked" | **Retained, narrowed** | `spawn_*` outcomes have a defined next-step skill; `auto-pass` verdicts have the escaped-defect closed loop. `inform_only` has neither. See Finding 1. |

## Recommendations

1. **F1 + F7** — decide FSM-2/FSM-4/FSM-2b policy. Recommended: FSM-2 → Option B variant (batch stamps `deferred`+reason at trip time); FSM-4 → Option A (`ratify.sh` single-commit); FSM-2b → Option A (batch stamps `stuck`+`wait_reason: unblock` on watchdog-timeout). Then file tickets. Also: add a `needs_decision` outcome to `create-review` (or a triage-queue mechanism) so design-level undecided reviews get a forcing function.
2. **F2** — add the `in-progress` interruption-recovery edge to `workflow-fsm.md` (either `in-progress → queued` re-queue, or `in-progress → stuck` on abandonment) and document it in `start-work` resume and `batch-work` trip-time stamping.
3. **F3** — `finish-work/SKILL.md` train-residue cleanup (follow-up to tkt-118; add `SKILL.md` to paths; rewrite `:23` pointer to "Sequential merge queue (§3.4)"; rewrite `:65,93,178,185,208,216` to drop `train-transient version reds` and reframe `Train landing` as generic multi-PR-queue guidance).
4. **F4** — add `docs/morning-triage.md` recipe.
5. **F5** — `workflow-fsm.md` M1 row: add `→ Spec done` terminal; document `Spec locked → Spec revised (supersede by new spc-N)` propagation to existing binders.
6. **F6** — `workflow-fsm.md` mermaid: add `any → closed` or annotate that the table is authoritative for cancel-from-any.

## Related

- `spc-42` (attention loop — FSM + SoT claims origin)
- ADR-004 §6 (binder status SoT) + §1 (human-owned white-list) + Amendment (tkt-90, snapshot-only honesty)
- ADR-005 (release-train retirement)
- `docs/workflow-fsm.md` §1–5
- `rev-20260827-064527Z-fsm-design-gaps` (prior FSM audit — FSM-2/FSM-4; this review adds FSM-2b and the doc/process gaps)
- `tkt-49` (reentry edges, closed), `tkt-90` (lifecycle closure, closed), `tkt-118` (train-docs retirement, closed), `tkt-123` (FSM observability, filed)
