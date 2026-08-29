# tkt-191 — Ticket binder created/updated timestamps

> **Status:** queued · kind feat · priority P1 · covers spc-186 A4

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | feat | |
| priority | P1 | |
| labels | feat, P1 | |
| github | https://github.com/percena/lattice/issues/191 | |
| status | queued | |
| created | 2026-08-29T11:09:34Z | |
| updated | 2026-08-29T11:09:34Z | |
| adopted | false | |
| summary | Ticket binders carry no created/updated timestamps (Specs/Reviews have them) — time-in-state uncomputable for in-flight tickets. Blocks A5. | |
| spec | spc-186 | |
| covers | A4 | |
| blocked_by | tkt-189 | vocabulary single-source lands first (shared validator/template files) |
| parallel_group | g2 | layer 2 |
| paths | skills/create-tickets/references/templates/ticket-binder.md, tools/validate-lattice-artifacts.py, skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/_lattice-lib/scripts/finish-ledger.sh, skills/_lattice-lib/scripts/ratify.sh, skills/_lattice-lib/scripts/lib/binder_rows.py | |
| solo_merge | true | one PR |
| primary_ticket | tkt-191 | |
| related_tickets | tkt-189, tkt-192 | 192 (staleness) depends on this |
| worktree_bind | tkt-191-binder-timestamps | |
| worktree | sibling `…/lattice.worktrees/tkt-191-binder-timestamps/` | |
| prs | (none) | |

## Acceptance (this slice)

- [x] Binder template + new binders carry `created`/`updated` (ISO-8601 UTC) field-table rows
- [x] All status-stamping scripts (stamp-pr-open, finish-ledger, ratify) bump `updated` atomically with the stamp
- [x] Validator: missing → warn (lazy migration); malformed → error
- [x] bats tests for the stamp-bumps

## Approach

Add `created`/`updated` rows to the ticket-binder template field table (placement decision: field table, per binder convention — Specs/Reviews use front matter, binders use the field table). create-tickets writes `created` at creation; each stamping script (stamp-pr-open.sh, finish-ledger.sh, ratify.sh) bumps `updated` in the same atomic write that flips status. Validator gains a lazy-migration warn (missing) + ISO-format error (malformed) — reusing the single-sourced status vocabulary from tkt-189 where applicable. No backfill of historical binders (lazy migration carries them).

## Anticipated decisions

- **Placement (field table vs front matter)** — pre-resolved: field table (binder convention; binders have no front matter).
- **Backfill historical binders** — pre-resolved: no; lazy-migration warn carries them.
- **ISO precision** — agent-decides: seconds precision (`YYYY-MM-DDTHH:MM:SSZ`); match finish-ledger's existing `mergedAt` format for consistency.

## Decision journal

- 2026-08-29: created from spc-186 POST_SPLIT (P1-4). Layer 2 behind tkt-189 (shared validator + template hot files).
- 2026-08-29: ISO precision → seconds (`YYYY-MM-DDTHH:MM:SSZ`) — resolved (source: pre-resolved anticipated decision; matches finish-ledger mergedAt + the `strftime("%Y-%m-%dT%H:%M:%SZ")` the stamping scripts already emit).
- 2026-08-29: `updated` bump posture → bump-if-present, never insert (source: agent-judgment; mirrors `fix_cycles` lazy-migration precedent — missing row is a no-op, the validator warns; new binders carry the row from the template so the bump takes effect going forward). Rejected insert-if-missing as more invasive and a risk to table integrity across three stamping scripts.
- 2026-08-29: shared bump helper → `binder_rows.stamp_updated()` in lib/binder_rows.py (source: preference; single-sources the binder-row write grammar like `merge_row`). Validator keeps validator-local `BINDER_TS_RE` (writers emit, never validate — same posture as `FIX_CYCLES_RE`; no parity test needed for a lib-only function). ratify wired to import binder_rows (was lib-free).
- 2026-08-29: idempotency preserved → bump gated on `s != orig` (real mutation) so a no-op re-run does not touch `updated` and the "no change (idempotent)" contract holds (source: agent-judgment; stamp-pr-open/finish-ledger idempotency tests assert byte-identical re-runs).

## Pending decisions

(none)

## Notes

- Blocked by tkt-189 (vocabulary single-source) — both touch tools/validate-lattice-artifacts.py and the ticket-binder template; serializing avoids merge conflict.
- A5 (staleness/water-level, tkt-192) is blocked by this ticket (needs timestamps to compute age).

## References

- Spec: spc-186 (`.lattice/specs/spc-186-hard-limit-closure.md`)
- Law: ADR-007 (`docs/adr/007-hard-limit-scope-law.md`)
- Review: rev-20260829-160834Z
- GH issue: #191

## Lineage

- Parent spec: spc-186
- Primary ticket: tkt-191
- Related: tkt-189 (blocker), tkt-192 (blocked by this)
- Covers: A4
- Blocked by: tkt-189
- Parallel group: g2
