# tkt-2-beta

| Field | Value |
| --- | --- |
| status | closed |
| fix_cycles | 2 |
| wait_reason | (none) |
| updated | 2026-09-01T10:00:00Z |
| spec | spc-100 |
| prs | pr-12 — https://github.com/acme/repo/pull/12 |

## Acceptance (this slice)

- [x] **A1** — done.

## Decision journal

<!-- Append-only during execution. -->
- 2026-09-01T12:00:00Z — batch-merge-gate escape authorized (ADR-007 §5b). rule_id=batch-merge-gate; reason="user-authorized: fixture"; authorizer=operator
- 2026-09-01T12:05:00Z — ci-gate waiver applied. rule_id=ci-gate; reason="infra-only failure"; authorizer=operator

## Pending decisions

<!-- (none yet) -->

## Attempts

- Try 1 — believed cause: fixture spawns a real server; delta: stub the port. Result: green.
- Try 2 — believed cause: flaky clock; delta: inject now. Result: green.

## Notes

