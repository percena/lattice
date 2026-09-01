# tkt-308 — create-adr: rev- precursor gate for reversing decisions

| Field | Value |
| --- | --- |
| id | tkt-308 |
| issue | #308 |
| slug | rev-precursor-gate |
| adopted | true |
| kind | bug |
| status | pr-open |
| ship | one-PR (batch #307–#310, primary tkt-307) |
| paths | `skills/create-adr/SKILL.md`, `skills/create-adr/references/policy.md` |

## Why

`create-adr` has no gate requiring a preceding `rev-` (`create-review`) evaluation for reversing/replacing decisions. An author can go straight to create-adr → create-tickets → start-work → code, bypassing create-review's Problem Audit. The up-front evaluation gate is never entered.

## Scope (In)

- `references/policy.md`: add "Reversing decision → preceding `rev-` (DEFAULT gate)" section — DEFAULT, skip requires recorded reason; pointer to create-review Problem Audit.
- `SKILL.md`: add core rule (reversing → preceding rev- DEFAULT; explicit skip reason); pointer to `../create-review`.

## Out

- INVARIANT enforcement (kept DEFAULT — trivial reversal may skip with reason).
- Non-reversing minimal ADRs (no precursor required).

## Acceptance (from issue)

- [x] create-adr policy + checklist: reversing/replacing decision → preceding rev- is DEFAULT; skip requires a recorded reason.
- [x] A pointer from create-adr to create-review for this class of decision.

## Notes

- Shares `create-adr` files with tkt-307 (reason for one-PR batch).
