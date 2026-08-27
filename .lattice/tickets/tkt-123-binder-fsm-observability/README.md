# tkt-123-binder-fsm-observability

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** binder FSM observability + bounded-loop enforcement — fix-cycle/retry counter field, rework-edge cleanup, stuck wait-reason
> **Kind:** feat · **Priority:** P2
> **Path:** (no Spec) → tkt-123 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/123 |
| status | closed |
| adopted | false |
| summary | binder FSM observability + bounded-loop enforcement (counter field, rework-edge cleanup, stuck wait-reason) |
| spec | (none — standalone process-hardening from state-machine audit) |
| covers | (none) |
| blocked_by | #121 |
| parallel_group | G2 |
| paths | skills/create-tickets/references/templates/ticket-binder.md, docs/workflow-fsm.md, tools/validate-lattice-artifacts.py |
| solo_merge | yes |
| **primary_ticket** | tkt-123 (this issue) |
| **related_tickets** | tkt-121 (shares validator file — stacked after) |
| **worktree_bind** | `tkt-123-binder-fsm-observability` |
| worktree | sibling `…/lattice.worktrees/tkt-123-binder-fsm-observability/` (default for shippable) |
| prs | pr-129 — https://github.com/percena/lattice/pull/129 |

## Acceptance (this slice)

- [x] **A1** The ticket-binder template gains a structured bounded-loop counter (e.g. a `fix_cycles` field-table row + a parseable marker in `## Attempts` recording review-fix cycles and retry counts) so caps are machine-readable, not append-only prose.
- [x] **A2** `docs/workflow-fsm.md` documents a **single** `rework` exit path (`rework → in-progress → fix → pr-open`); the redundant direct `rework → pr-open` edge is removed or clarified with the condition that distinguishes it; the ≤2 cycle counter is tied to the A1 field.
- [x] **A3** The binder template gains a `wait_reason: unblock | re-scope` convention (field or `## Notes` marker) so morning triage can route `stuck` tickets: unblock (needs an answer) vs re-scope (needs Spec/ticket revision, routed to M1). `start-work`/`workflow-fsm.md` reference it.
- [x] **A4** `validate-lattice-artifacts.py` statically flags a bounded-loop counter exceeding its declared bound (e.g. `fix_cycles > 2`), reusing the warning posture from legacy-status lazy migration.
- [x] **A5** Live `.lattice/` tree passes the validator (existing binders without the new field warn, not fail — lazy migration precedent).

## Approach

- A1: add to `ticket-binder.md` field table:
  ```
  | fix_cycles | 0 | review-fix cycles on this PR (cap ≤2 per ADR-004 §5; validator warns >2) |
  ```
  and a parseable `cycle: N` line convention in `## Attempts` so the validator can read it without parsing free prose.
- A2: in `workflow-fsm.md` M2 diagram + transition table, collapse the two `rework →` rows into the real path; add a one-line note that `rework → pr-open` only fires on push (the completion of the fix cycle), and the counter lives in `fix_cycles`.
- A3: add `wait_reason` to the template + a short note in `start-work` SKILL.md's `stuck` resume bullet and `workflow-fsm.md`'s `stuck` rows.
- A4: extend `validate-lattice-artifacts.py` to parse `fix_cycles` (field table) and emit `bound_exceeded` warning when >2; mirror the `legacy_open_status` warning pattern.
- A5: lazy-migration — missing `fix_cycles`/`wait_reason` on existing binders is a warning at most (or silent), never a fail.

## Anticipated decisions

- Counter shape (field-table row vs `## Attempts` marker vs both) — disposition: must-ask (cross-contract: binder template is the writer contract for every skill; pick the shape that every skill can stamp without fork). Default if unanswered: field-table `fix_cycles` row (single source, validator-parseable).
- Whether `wait_reason` is a field-table row or a `## Notes` marker — disposition: agent-decides (reversible + local; field-table is more grep-able, marker is lower-friction).
- Bound-exceeded posture: warning vs error — disposition: pre-resolved (warning, lazy-migration precedent; the cap is agent-discipline, the validator surfaces drift, not blocks).

## Decision journal

<!-- append-only -->

## Pending decisions

<!-- (none yet) -->

## Attempts

<!-- (none) -->

## Notes

- FSM-2 (SoT honesty after fuse/blocked-by-failure — `queued` binder lies about schedulability) and FSM-4 (parked→queued atomicity claim unenforced) are **design-philosophy gaps**, filed as a review note `rev-20260827-064527Z-fsm-design-gaps.md` — not this ticket.
- Shares `tools/validate-lattice-artifacts.py` with tkt-121 — **stacked on #121**.

## References

- GitHub issue body: https://github.com/percena/lattice/issues/123
- ADR-004 §5 (bounded-loop invariant), §6 (binder status SoT)
- `docs/workflow-fsm.md` (M2 machine + transition table)
- `skills/_lattice-lib/references/fallback-policy.md` (caps)

## Lineage

- Parent spec: (none)
- Parent issue: (none — ticket-only)
- Primary ticket: **tkt-123**
- Related / sub-tickets: tkt-121 (blocked_by inverse)
- Covers: (none)
- Blocked by: **#121** (shares `validate-lattice-artifacts.py`)
- Parallel group: G2
- Worktree bind: `tkt-123-binder-fsm-observability`

## Assets

Local files in `./assets/`.

## Finish


- pr-129 merged: 2026-08-27T07:30:12Z — https://github.com/percena/lattice/pull/129 (base merge)
- issue #123 closed: 2026-08-27T07:30:19Z — https://github.com/percena/lattice/issues/123
