# tkt-309 — create-review: Problem Audit existing-solution + comparison matrix

| Field | Value |
| --- | --- |
| id | tkt-309 |
| issue | #309 |
| slug | problem-audit-matrix |
| adopted | true |
| kind | bug |
| status | pr-open |
| created | 2026-09-01T00:00:00Z |
| updated | 2026-09-01T00:00:00Z |
| ship | one-PR (batch #307–#310, primary tkt-307) |
| paths | `skills/create-review/SKILL.md`, `skills/create-review/references/policy.md`, `skills/create-review/references/templates/review.md` |

## Why

create-review's Problem Audit audits validity/info-sufficiency/hidden-issues but does not explicitly ask "does an existing solution already meet the stated goal?" — the question that surfaces a redundant replacement. And for decision-support reviews comparing options, there is no required multi-dimensional comparison matrix, so options are weighed by vibes/confirmation bias.

## Scope (In)

- `references/policy.md`: Problem Audit table add "Existing solution" row; add comparison matrix DEFAULT requirement for design/audit reviews.
- `SKILL.md`: update rule 1b to name existing-solution + comparison matrix.
- `references/templates/review.md`: add Existing-solution row to Problem Audit table; add `## Comparison matrix` section.

## Out

- Other review kinds (`dogfood`, `research`) stay free-form.

## Acceptance (from issue)

- [x] Problem Audit checklist includes the existing-solution-meets-goal question.
- [x] Decision-support (option-comparing) reviews require a multi-dimensional comparison matrix.
