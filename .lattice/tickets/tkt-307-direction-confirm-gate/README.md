# tkt-307 — create-adr: Goal + status-quo option for reversing decisions

| Field | Value |
| --- | --- |
| id | tkt-307 |
| issue | #307 |
| slug | direction-confirm-gate |
| adopted | true |
| kind | bug |
| status | pr-open |
| created | 2026-09-01T00:00:00Z |
| updated | 2026-09-01T00:00:00Z |
| ship | one-PR (primary of batch #307–#310) |
| paths | `skills/create-adr/SKILL.md`, `skills/create-adr/references/policy.md`, `skills/create-adr/references/templates/adr.md` |

## Why

`create-adr` marks `## Considered Options` as optional and has no required `## Goal` field. For reversing/replacing decisions the status quo is never evaluated as a real alternative against the real goal, so a decision can be built out before anyone notices the existing solution already meets the goal with less work.

## Scope (In)

- `references/templates/adr.md`: add `## Goal` field (required for reversing, optional otherwise); make `## Considered Options` require a "keep status quo" row evaluated against Goal for reversing decisions.
- `references/policy.md`: add a "Reversing / replacing decisions (status-quo gate)" section making Goal + Considered Options (+ status-quo row) INVARIANT for reversing decisions; non-reversing Nygard-minimal unchanged.
- `SKILL.md`: update body section list to include Goal; add Verification checklist lines.

## Out

- Non-reversing minimal ADR behavior (unchanged).
- No runtime/production code.

## Acceptance (from issue)

- [x] create-adr policy + template: for reversing/replacing decisions, Goal + Considered Options (+ status-quo row) are required.
- [x] A checklist line flags a missing status-quo row or a status-quo dismissal not tied to Goal.
- [x] Minimal (non-reversing) ADRs unchanged.

## Notes

- Shipped in one PR with tkt-308 (same files), tkt-309 (create-review), tkt-310 (start-work).
- Bug-class, no Reproduction Steps in issue → Phase 0c note: cannot reproduce without steps; policy/template gap is the brief.
