# tkt-411-test-fixtures-single-source

> **TL;DR:** `validators-hardening.bats:69` hard-codes catalog size `-eq 15` and `validate-skills.bats:41` hand-duplicates the USER_FACING list — a new user-facing skill breaks CI until both are edited. Derive both from the single source (`tools/validate-skills.sh` `USER_FACING[]`).
> **Kind:** enhancement · **Priority:** P3
> **Path:** tkt-411 → (pr-…)

| Field | Value |
| --- | --- |
| kind | enhancement |
| priority | P3 |
| labels | enhancement, P3 |
| github | https://github.com/percena/lattice/issues/411 |
| status | in-progress |
| adopted | true |
| summary | derive USER_FACING list + catalog size in bats fixtures from tools/validate-skills.sh single source |
| spec | none |
| covers | A1, A2 |
| blocked_by | none |
| parallel_group | (serial — batch with tkt-409/410/412) |
| paths | tools/tests/validators-hardening.bats, tools/tests/validate-skills.bats |
| solo_merge | no (batch PR) |
| **primary_ticket** | tkt-411 |
| **related_tickets** | tkt-409, tkt-410, tkt-412 (NOTICED-drain batch) |
| **worktree_bind** | tkt-409-noticed-drain-fixes |
| worktree | sibling …/lattice.worktrees/tkt-409-noticed-drain-fixes/ |
| prs | pending |

## Acceptance (this slice)

- [x] **A1** `validate-skills.bats` no longer hand-duplicates the USER_FACING list — it sources or extracts the array from `tools/validate-skills.sh`, so adding a user-facing skill updates the fixture automatically.
- [x] **A2** `validators-hardening.bats` catalog-size assertion no longer hard-codes `-eq 15` — it derives the expected count from the single source (or counts `evals/routing` cases dynamically), so the test tracks reality instead of a magic number.

## Approach

`tools/validate-skills.sh` defines `USER_FACING=(...)` (the canonical list). `run-routing-evals.py` keeps a set-equal list, asserted by `tools/tests/routing-catalog-parity.bats`. Two options for the bats fixtures: (a) `source` validate-skills.sh and read `USER_FACING[@]` (bash-array introspection), or (b) compute the count by listing `evals/routing/*.json` case files (the routing catalog). Prefer (a) for the list and derive the count from the sourced array length, keeping one source of truth. Validate with `bats` that the green fixture still passes and the count assertion tracks an added/removed skill.

## Decision journal

## Pending decisions

## Attempts

## Notes

- NOTICED in tkt-373. Filed by tkt-386 NOTICED backlog drain.
- The `validate-skills.bats` fixture builds a synthetic green tree; sourcing validate-skills.sh for the list must not execute its validation pass (guard with a function or extract the array via `sed`/`grep` if sourcing has side effects).

## References

- tools/validate-skills.sh (USER_FACING single source) · run-routing-evals.py:26-28 · routing-catalog-parity.bats

## Lineage

- Parent spec: none · Primary ticket: tkt-411 · Parallel group: (serial NOTICED-drain batch) · Worktree bind: `tkt-409-noticed-drain-fixes`

## Finish
