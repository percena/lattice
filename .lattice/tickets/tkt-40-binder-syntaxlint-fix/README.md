# tkt-40-binder-syntaxlint-fix

> **TL;DR:** Fix tkt-35 binder checkbox hygiene + add PyYAML availability check note to syntax-lint.md
> **Kind:** fix · **Status:** open · **Priority:** P3

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P3 |
| labels | bug, P3 |
| github | https://github.com/percena/lattice/issues/40 |
| status | closed |
| adopted | false |
| summary | fix binder checkbox hygiene + syntax-lint.md PyYAML availability check |
| spec | (none — review-fix) |
| covers | A1, A2 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | .lattice/tickets/tkt-35-split-lint-heavy/README.md, skills/review-code/references/syntax-lint.md |
| solo_merge | yes |
| **primary_ticket** | tkt-40 (this issue) |
| **related_tickets** | tkt-35 (split-lint-heavy) |
| **worktree_bind** | tkt-40-binder-syntaxlint-fix |
| prs | pr-41 — https://github.com/percena/lattice/pull/41 |

## Acceptance (this slice)

- [x] **A1** tkt-35-split-lint-heavy binder: A1/A2/A4 checkboxes are `- [x]`; A3 stays `- [ ]`
- [x] **A2** syntax-lint.md: YAML tool row notes `python3 -c "import yaml"` as the availability check; ImportError → skip gracefully

## Notes

- Source: review-code pass on dev→main final review (2026-08-25)
- Two low-severity findings batched into one ticket

## References

- GitHub issue body is SoT for long prose

## Finish

- pr-41 merged: 2026-08-25T12:38:19Z — https://github.com/percena/lattice/pull/41 (base merge)
- issue #40 closed: 2026-08-25T12:38:35Z — https://github.com/percena/lattice/issues/40
