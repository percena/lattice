# tkt-310 — start-work: COMMITTED direction-confirmed-via field

| Field | Value |
| --- | --- |
| id | tkt-310 |
| issue | #310 |
| slug | direction-field |
| adopted | true |
| kind | bug |
| status | pr-open |
| created | 2026-09-01T00:00:00Z |
| updated | 2026-09-01T00:00:00Z |
| ship | one-PR (batch #307–#310, primary tkt-307) |
| paths | `skills/start-work/SKILL.md` |

## Why

start-work's COMMITTED card records Why/In/Out/Acceptance/mode/workspace/ship but not how the underlying direction was confirmed. When a direction is assumed (no accepted ADR, no concluded rev-, not user-stated), the card still proceeds to EXECUTE — so "build before confirming the direction" is silent rather than surfaced.

## Scope (In)

- `SKILL.md`: COMMITTED card add `Direction confirmed via: ADR-NNN | rev-… | user-stated | assumed`; add rule that `assumed` triggers a batch-confirm before product EXECUTE; update Verification checklist.

## Out

- No change to the existing "new irreversible/high-stakes axis → PCA batch" rule (complements, not replaces).

## Acceptance (from issue)

- [x] COMMITTED card includes a Direction-confirmed-via field.
- [x] `assumed` triggers a batch-confirm before EXECUTE (not a silent proceed).
