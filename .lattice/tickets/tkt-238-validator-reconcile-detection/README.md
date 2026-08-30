# tkt-238 — validator + reconcile-state detection defects

> **Status:** open · kind bug · priority P1 · post-merge dev→main review follow-up

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | bug | |
| priority | P1 | |
| labels | bug,P1 | |
| github | https://github.com/percena/lattice/issues/238 | |
| status | closed | |
| summary | See issue #238 body for full confirmed findings + recommended fixes (file:line, failure scenarios). | |
| spec | (none — ticket-only) | post-merge review follow-up, no Spec parent |
| covers | (none — ticket-only) | |
| blocked_by | (none) | no inter-ticket deps; disjoint paths |
| parallel_group | review-fixes | all 8 tickets, disjoint paths, single layer |
| paths | tools/validate-lattice-artifacts.py, skills/_lattice-lib/scripts/reconcile-state.sh, tools/tests/lattice-artifacts.bats, skills/_lattice-lib/scripts/tests/reconcile-state.bats | disjoint from all sibling tickets |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-238 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T10:27:07Z | |

## Acceptance (this slice)

Implement every confirmed finding listed in issue #238 body, with the recommended fix applied. Re-run the relevant `bats` suite + `ci-local.sh` (or `--fast`) green before opening the PR. Open PR via `create-pr` targeting `dev` (base = integration branch per ADR-005; version bump deferred to dev→main). Stop at create-pr — do NOT call finish-work (batch marker active).

Full finding list (file:line + failure scenario + fix): https://github.com/percena/lattice/issues/238

## Finish

- pr-245 merged: 2026-08-30T10:26:33Z — https://github.com/percena/lattice/pull/245 (base merge)
- issue #238 closed: 2026-08-30T10:26:39Z — https://github.com/percena/lattice/issues/238
