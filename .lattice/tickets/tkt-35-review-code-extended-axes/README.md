# tkt-35-review-code-extended-axes

> **TL;DR:** Add CI/CD, syntax/lint, docs-sync, interface-impact axes + solution-oriented findings + batch confirmation to review-code skill (not finish-work mini-review)
> **Kind:** enhancement · **Status:** open · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | enhancement |
| priority | P2 |
| labels | review-code, skill, quality |
| github | https://github.com/percena/lattice/issues/38 |
| status | open |
| adopted | false |
| summary | extend review-code with CI/CD, syntax/lint, docs-sync, interface-impact axes; solution-oriented findings; single batch confirmation |
| spec | (none — review-fix / ADR-driven) |
| covers | A1, A2, A3, A4, A5, A6 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/review-code/SKILL.md, skills/review-code/references/ci-check.md, skills/review-code/references/syntax-lint.md, skills/review-code/references/docs-sync.md, skills/review-code/references/interface-impact.md, skills/review-code/references/finding-contract.md, skills/review-code/evals/evals.json, docs/adr/003-review-code-extended-axes-and-solution-oriented-findings.md, docs/adr/README.md, CHANGELOG.md |
| solo_merge | yes |
| **primary_ticket** | (this) |
| **related_tickets** | (none) |
| **worktree_bind** | (to be bound at start-work) |
| prs | (none) |
| adr | ADR-003 |

## Acceptance (this slice)

- [x] **A1** CI/CD axis — `references/ci-check.md` created; PR/branch CI status fetch, log excerpt, failure classification, no-CI handling
- [x] **A2** Syntax/Lint axis — `references/syntax-lint.md` created; tool selection by extension, severity rules, graceful skip
- [x] **A3** Docs sync axis — `references/docs-sync.md` created; doc locations, stale detection, severity
- [x] **A4** Interface/contract impact axis — `references/interface-impact.md` created; change type table, git grep consumer tracing, one-hop boundary
- [x] **A5** Solution-oriented findings — finding-contract.md + SKILL.md Step 4 upgraded to 5-item bar (recommended solution + alternatives); output template gains `### Solutions` subsection; Step 6 batch confirmation with solution-level options
- [x] **A6** Consistency — step numbering (1-7), cross-references, hard-stop invariant, evals (9 cases), validate-skills pass; finish-work mini-review unchanged

## Notes

- Decision rationale: see ADR-003 (`docs/adr/003-review-code-extended-axes-and-solution-oriented-findings.md`)
- finish-work mini-review deliberately NOT extended — stays bounded 5-axis projection
- review-context.py intentionally unchanged — stays pure git-context gatherer
- Self-review found and fixed 6 consistency issues: Step 3 naming (Automated→Auxiliary), interface-impact.md cross-ref (Step 2→Step 3), ci-check.md axis list missing interface impact, dig-deeper missing interface breakage, output subsection order, reference hard-stop wording aligned to batch confirmation

## References

- ADR-003: `docs/adr/003-review-code-extended-axes-and-solution-oriented-findings.md`
- ADR template: `skills/create-adr/references/templates/adr.md`

## Finish

- (pending — PR to be opened, issue to be filed)
