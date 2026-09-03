# tkt-237 — spec-supersede atomicity + stamp-pr-open deferred-state + verify-mutation safety-net

> **Status:** open · kind bug · priority P2 · post-merge dev→main review follow-up

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | bug | |
| priority | P2 | |
| labels | bug,P2 | |
| github | https://github.com/percena/lattice/issues/237 | |
| status | closed | |
| summary | See issue #237 body for full confirmed findings + recommended fixes (file:line, failure scenarios). | |
| spec | (none — ticket-only) | post-merge review follow-up, no Spec parent |
| covers | (none — ticket-only) | |
| blocked_by | (none) | no inter-ticket deps; disjoint paths |
| parallel_group | review-fixes | all 8 tickets, disjoint paths, single layer |
| paths | skills/_lattice-lib/scripts/spec-supersede.sh, skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/_lattice-lib/scripts/lib/status_vocab.py, skills/_lattice-lib/scripts/verify-mutation.sh, skills/_lattice-lib/scripts/tests/ | disjoint from all sibling tickets |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-237 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T10:44:27Z | |

## Acceptance (this slice)

Implement every confirmed finding listed in issue #237 body, with the recommended fix applied. Re-run the relevant `bats` suite + `ci-local.sh` (or `--fast`) green before opening the PR. Open PR via `create-pr` targeting `dev` (base = integration branch per ADR-005; version bump deferred to dev→main). Stop at create-pr — do NOT call finish-work (batch marker active).

Full finding list (file:line + failure scenario + fix): https://github.com/percena/lattice/issues/237

## Finish

- pr-248 merged: 2026-08-30T10:44:01Z — https://github.com/percena/lattice/pull/248 (base merge)
- issue #237 closed: 2026-08-30T10:44:08Z — https://github.com/percena/lattice/issues/237
