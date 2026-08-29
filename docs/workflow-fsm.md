# Workflow FSM (three coupled machines)

The Lattice delivery workflow, formalized as three coupled state machines: **M1 planning** (day, attended), **M2 execution** (night, per ticket, unattended), **M3 knowledge** (slow variable).
Sources: `spc-42` · `ADR-004` · `rev-20260826-141124Z` (Finding 7). Day-side recipe: [day-phase.md](./day-phase.md).

---

## 1. The three machines

| Machine | Scope | Cadence | States |
| --- | --- | --- | --- |
| **M1 planning** | one feature | day, attended | requirement → dialogue → proposal rev → sign-off → Spec locked → ADR (conditional) → tickets → Spec `done` |
| **M2 execution** | one ticket | night, unattended | `queued` → `in-progress` → `pr-open` (+ side states `parked` / `stuck` / `rework` / `deferred`; terminal `closed`) |
| **M3 knowledge** | one decision | slow | journal entry → ratified ×2 → promotion proposal → preferences entry → superseded-with-date |

They couple at the edges: M1 emits tickets into M2's queue; M2 emits decisions into M3's journal and can send scope escapes back to M1 (Spec revision); M3 feeds resolved preferences back into M2's decision policy.

### M1 — planning

Entry edges (not all tickets pass through every stage):

```text
business requirement (PM)                         ← primary entry
   → architecture dialogue (evidence-first rounds)
   → solution-proposal rev (2–3 options + recommendation)
   → human macro sign-off (multiple choice)
   → Spec locked (create-spec)
   → ADR when cross-feature (create-adr)
   → tickets (create-tickets: anticipated-decisions scan + ## Approach)
   → Spec done (finish-work stamps when workstream complete; all child tickets closed)

review spawn_spec      → Spec locked              ← review-driven entry (create-review)
review spawn_tickets   → tickets (M2 queue)       ← review short-circuits to execution
review spawn_fix       → fix ticket (M2 queue)    ← targeted fix from review findings
verify-features        → bug ticket (M2 queue)    ← runtime verification files bugs w/ repro
S-class fast path      → direct ticket (M2 queue) ← small/trivial: Spec implicit, minimal dialogue
```

Spec revision = supersede with a new `spc-N` (never silent rewrite of id, per `create-spec`); the old Spec's still-active child binders are stamped `deferred` + `spec-superseded` **at supersede time** by `spec-supersede.sh` (spc-186 A3 / tkt-190 — trip-time honesty, generalizing tkt-136/137) — finish-work's land-time Spec drift stays as a backstop. Spec status enum: `draft | locked | done | superseded`.

### M2 — execution (per ticket)

```mermaid
stateDiagram-v2
    state "in-progress" as ip
    state "pr-open" as pr
    [*] --> queued
    queued --> ip: spawn / bind
    queued --> deferred: fuse-halt stamps at trip time (ADR-004 amd tkt-136)
    queued --> deferred: spec-superseded stamps at supersede time (spc-186 A3)
    ip --> deferred: spec-superseded stamps at supersede time (spc-186 A3)
    deferred --> queued: re-schedule
    ip --> pr: PR opened
    ip --> parked: park & pivot (unresolvable decision)
    parked --> queued: ratify (ratify.sh single-commit + re-queue)
    ip --> stuck: fallback bounds hit
    ip --> stuck: watchdog-timeout / abandonment (host stamps at trip time)
    stuck --> queued: unblock
    pr --> rework: findings returned (new brief)
    rework --> ip: fix cycle (fix_cycles ≤2; then ip→pr on push)
    rework --> deep-review: third rework return (cap-exit, human — no auto-retry)
    stuck --> [*]: re-scope → M1 (Spec/ticket revision)
    pr --> closed: human merge (day)
    stuck --> closed: cancel
    closed --> [*]
```

Cancel edge: any working state → `closed` (without merge) is a valid cancel edge — the transition table (§2) is authoritative for cancel-from-any-state.

Fuse edge: a batch fuse halt now stamps affected tickets `deferred` + a reason (`fuse-halt`) at trip time (ADR-004 Amendment tkt-136, Option B) so the SoT reflects "not schedulable"; `deferred → queued` remains a human transition (re-schedule into a later batch). Blocked-by-failure dependents likewise stamp `deferred` + reason `blocked-by-failure`. A watchdog-timeout/crash of an already-spawned ticket stamps `stuck` + `wait_reason: unblock` (FSM-2b, tkt-132) — the SoT reflects "needs human investigation," not "active work."

Review path from `pr-open`: chain review (`review-delivery`, artifact-only) → bounded fix cycle (≤2) for material findings → verdict `auto-pass | ratify-then-pass | deep-review` → **human merge**. The fix cycle is owned by `bump-fix-cycle.sh` (`_lattice-lib/scripts/`), called at the procedural stamp point (finish-work mini-review Hold, review-delivery `--with-review`): it stamps `pr-open → rework` and bumps `fix_cycles` atomically. On the third rework return the cap-exit fires — `fix_cycles` holds at 2 and the CAP-HIT trace forces the `deep-review` triage class (human) before any further fix cycle; no auto-retry (ADR-007 §4 five-piece; spc-186 A6). A materially changed rebase voids the verdict (clean rebase carries it). `stuck` also exits sideways to M1 (re-scope → Spec/ticket revision) — a scope escape is a planning defect, not an execution problem.

### M3 — knowledge

```text
decision journal entry (cites its resolution source)
   → ratified ×2 (morning triage)
   → promotion proposal (in the digest)
   → .lattice/preferences.md entry (INVARIANT / DEFAULT / HINT)
   → superseded with a date (never deleted)

operator-stated preference (mid-session utterance)
   → written to .lattice/preferences.md AT UTTERANCE TIME by the active skill
     (Capture duty, decision-policy.md — provenance `operator-stated`; pr-88)
   → superseded with a date (never deleted)
```

The ×2-promotion path is for journal-derived candidates; an explicit operator directive takes the direct edge — the agent writes it immediately with provenance and confirms in one line. Spec/ADR always outrank preferences.

---

## 2. Transition table

Owner legend: **human** (attention-contract white-list, §3) · **agent** (delegable under policy) · **system** (scripts/orchestrator on durable artifacts).

### M1 planning

| State → State | Trigger | Owner |
| --- | --- | --- |
| — → requirement | PM brings a business requirement | human |
| review → Spec locked | `create-review` outcome `spawn_spec` — review spawns a new Spec directly | agent |
| review → tickets (M2) | `create-review` outcome `spawn_tickets` / `spawn_fix` — review short-circuits to execution | agent |
| verify-features → bug ticket (M2) | runtime verification files bugs as tickets with repro steps (enters M2 directly) | agent |
| S-class → ticket (M2) | small/trivial change: Spec implicit, minimal dialogue, direct ticket (start-work `mode: S`) | human / agent |
| requirement → proposal rev | evidence pass + 2–3 candidate architectures + recommendation | agent |
| proposal rev → Spec locked | **macro sign-off** (multiple choice) → `create-spec` | human |
| Spec locked → ADR | cross-feature law promoted via `create-adr` | agent |
| Spec → tickets | `create-tickets` split (anticipated-decisions scan, `## Approach`) | agent |
| Spec locked → Spec revised | **Spec revision** (incl. execution-discovered, routed from M2 `stuck`) | human |

### M2 execution

| State → State | Trigger | Owner |
| --- | --- | --- |
| queued → in-progress | batch-work spawn / start-work bind | system |
| queued → deferred | fuse-halt / blocked-by-failure stamps `deferred`+reason at trip time (ADR-004 amd tkt-136 Option B); or deliberate human deschedule | system / human |
| deferred → queued | re-scheduled into a later batch | human |
| in-progress → pr-open | `create-pr` opens the PR | agent |
| in-progress → parked | irreversible / cross-contract decision, unattended → park & pivot | agent |
| in-progress → stuck | fallback bounds hit OR watchdog-timeout/abandonment; Attempts ledger complete + one well-formed question; binder `wait_reason` stamped (`unblock` \| `re-scope`) so morning triage routes the two different dispositions | agent / system |
| parked → queued | **decision ratification** via `ratify.sh` (single-commit: journal entry + status flip in one git commit; crash window narrowed, not eliminated — ADR-004 amd tkt-136 Option A) | human |
| stuck → queued | unblock (answer / env fix) — `wait_reason: unblock` | human |
| stuck → M1 | re-scope: **Spec revision** / ticket revision — `wait_reason: re-scope` | human |
| pr-open → rework | PR returned with findings (findings become the new brief); `bump-fix-cycle.sh` is the procedural stamp point — stamps `status: rework` + bumps `fix_cycles` atomically (spc-186 A6). Called by finish-work mini-review Hold and review-delivery `--with-review` fix loop | system |
| rework → in-progress | re-enters the queue, address-review shape; `fix_cycles` row stamps the round (ADR-004 §5 cap ≤2). The path is `rework → in-progress → (implement fix) → pr-open` — there is no direct `rework → pr-open`; on push, `in-progress → pr-open` fires (the existing transition), and `fix_cycles` increments | system |
| rework → deep-review (cap-exit) | **third rework return** — `fix_cycles` would exceed the ≤2 cap. `bump-fix-cycle.sh` holds `fix_cycles` at 2, stamps `rework`, and journals a CAP-HIT trace that FORCES the `deep-review` triage class (human) before any further fix cycle — **no auto-retry** (ADR-007 §4 five-piece hard rule; spc-186 A6). Escape: `--extend-budget --reason "<operator-adjudicated rationale>"` authorizes one more cycle (human, double-confirm; no agent self-adjudication) | human |
| pr-open → pr-open (verdict voided) | materially changed rebase → re-review; clean rebase carries the verdict | system |
| pr-open → closed (merged) | **merge** — day only; `finish-ledger.sh` stamps `mergedAt` | human |
| any → closed (without merge) | **cancel** | human |

### M3 knowledge

| State → State | Trigger | Owner |
| --- | --- | --- |
| decision point → journal entry | self-decision under decision policy, resolution source cited | agent |
| journal entry → ratified | morning **decision ratification** | human |
| ratified ×2 → promotion proposal | digest proposes promotion to preferences | system |
| proposal → preferences entry | human accepts | human |
| operator utterance → preferences entry | **Capture duty** — durable operator-stated preference written at utterance time, provenance `operator-stated` (decision-policy.md, pr-88) | agent |
| preferences entry → superseded | replaced with a dated supersede (never deleted) | human |

---

## 3. Human-owned transitions (attention contract)

A **closed white-list** — everything not on it is delegable under policy (ADR-004 §1):
Morning triage recipe: [morning-triage.md](./morning-triage.md).

1. **Macro sign-off** (proposal rev → Spec)
2. **Decision ratification** (journal / parked wake-up)
3. **Deep-review verdict**
4. **Spec revision**
5. **Cancel**
6. **Merge** (nights never merge — batch marker gate unchanged)

---

## 4. Safety invariants

| Invariant | Detail |
| --- | --- |
| Night states never reach merged | the `.lattice/.batch-work-active` marker gates merge; merge authority is human, day-side |
| Transitions fire only on durable artifacts | binder / Spec / PR / ledger writes — never on chat or transcript state |
| Every decision transition is journaled | each self-decision cites its resolution source in `## Decision journal` |
| Every autonomous loop declares an upper bound | existing bounds: PCA ≤5 rounds · bug-repro ≤2 cycles · review-fix ≤2 cycles (cap-exit → `deep-review`, human — `bump-fix-cycle.sh`; no auto-retry) · retry ≤2/path and ≤3 paths/ticket |

---

## 5. Where M2 state lives

The binder field-table **`status`** is the single source of truth for M2 state (ADR-004 §6): working states `queued | in-progress | parked | stuck | pr-open | rework | deferred`, terminal `closed` — merged vs closed-without-merge is read from the `## Finish` ledger's `mergedAt`, not from a separate status value. The vocabulary + coupled-field transition policy (side-state guard, direct-jump rules) are machine-readable and single-sourced in `skills/_lattice-lib/scripts/lib/status_vocab.py`, consumed by `reconcile-state.sh`, `finish-ledger.sh`, and `stamp-pr-open.sh`; `validate-lattice-artifacts.py` vendors a parity-checked copy so consumer repos can vendor the validator alone (tkt-189 / spc-187 A2). `stamp-pr-open.sh` refuses to overwrite a side state (`parked` / `stuck` / `rework`) with `pr-open` without an explicit `--force-side-state --reason` override that journals a structured operator-adjudicated trace (ADR-007 §5b); a direct `queued → pr-open` jump is allowed but WARN-journaled so the "started" signal is not silently lost. Legacy `open` is accepted as a coarse value during lazy migration (validator warns). State is never inferred from PR, marker, or worktree existence alone. `validate-lattice-artifacts.py` enforces this statically per snapshot — unknown status values (`invalid_ticket_status`), terminal status without a Finish ledger (`closed_without_finish`), a merged Finish ledger without terminal status (`finish_without_terminal_status`), and duplicate ticket ids (`duplicate_ticket_id`); it does not replay transition history, so edge legality between two valid snapshots is owned by the skills that perform the transitions (amendment history in ADR-004).

**Trip-time stamping:** fuse-halt and blocked-by-failure stamp `deferred`+reason at trip time; watchdog-timeout/abandonment stamps `stuck`+`wait_reason: unblock` (FSM-2b). The binder SoT is honest about schedulability across runs. `parked → queued` ratification is performed by `ratify.sh` (`_lattice-lib/scripts/`) — single git commit for journal entry + status flip (crash window narrowed, not eliminated). Amendment history in ADR-004.
