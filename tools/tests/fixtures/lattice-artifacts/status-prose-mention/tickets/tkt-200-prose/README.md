# tkt-200-prose

<!-- Regression (tkt-121 P2): binder card (first table) has NO status row.
     Body prose mentions the literal **Status:** marker — it must NOT be
     misread as the ticket status. The scoped fallback (tldr_header_status,
     blockquote lines before the first table) finds no header status, and
     front-matter has none, so status resolves to None (no finding). -->

| Field | Value |
| --- | --- |
| kind | bug |
| github | https://github.com/percena/lattice/issues/200 |
| covers | (none) |

## Acceptance

- [ ] The binder **Status:** field must be bogusfield after a returned PR.

## Finish

- (none yet)
