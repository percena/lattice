# Workflow FSM reference (portable)

> Portable excerpt of `docs/workflow-fsm.md` (monorepo). The full doc is
> authoritative when present; this reference carries the essential state
> machine, vocabulary, and safety invariants so installed skills remain
> self-contained in a vendored install (no monorepo `docs/` required).

## Three coupled machines

| Machine | Scope | Cadence | States |
| --- | --- | --- | --- |
| **M1 planning** | one feature | day, attended | requirement → dialogue → proposal rev → sign-off → Spec locked → ADR (conditional) → tickets → Spec `done` |
| **M2 execution** | one ticket | night, unattended | `queued` → `in-progress` → `pr-open` (+ side states `parked` / `stuck` / `rework` / `deferred`; terminal `closed`) |
| **M3 knowledge** | one decision | slow | journal entry → ratified ×2 → promotion proposal → preferences entry → superseded-with-date |

## M2 status vocabulary (single-source: `status_vocab.py`)

Working: `queued | in-progress | parked | stuck | pr-open | rework | deferred`
Terminal: `closed` — merged vs closed-without-merge is read from the `## Finish` ledger's `mergedAt`.

The binder field-table **`status`** is the single source of truth for M2 state (ADR-004 §6). `stamp-pr-open.sh` refuses to overwrite a side state (`parked`/`stuck`/`rework`) with `pr-open` without an explicit `--force-side-state --reason` override. A direct `queued → pr-open` jump is allowed but WARN-journaled.

## Entry edges

- PM requirement → full M1 dialogue (primary entry)
- Review `spawn_spec` → Spec locked (review-driven)
- Review `spawn_tickets` / `spawn_fix` → M2 queue (short-circuit to execution)
- verify-features → bug ticket (M2 queue, with repro steps)
- S-class fast path → direct ticket (small/trivial, Spec implicit)

## Human-owned transitions (attention contract — ADR-004)

1. Macro sign-off (proposal rev → Spec)
2. Decision ratification (journal / parked wake-up)
3. Deep-review verdict
4. Spec revision
5. Cancel
6. Merge (nights never merge — batch marker gate)

## Safety invariants

| Invariant | Detail |
| --- | --- |
| Night states never reach merged | the `.lattice/.batch-work-active` marker gates merge; merge authority is human, day-side |
| Transitions fire only on durable artifacts | binder / Spec / PR / ledger writes — never on chat or transcript state |
| Every decision transition is journaled | each self-decision cites its resolution source in `## Decision journal` |
| Every autonomous loop declares an upper bound | PCA ≤5 · bug-repro ≤2 · review-fix ≤2 (cap-exit → deep-review, human) · retry ≤2/path, ≤3 paths/ticket |

## Trip-time stamping

Fuse-halt and blocked-by-failure stamp `deferred`+reason at trip time.
Watchdog-timeout/abandonment stamps `stuck`+`wait_reason: unblock`.
`parked → queued` ratification via `ratify.sh` (single-commit).

---

_See `docs/workflow-fsm.md` in the monorepo for the full transition table, M3 knowledge machine, and amendment history (ADR-004)._
