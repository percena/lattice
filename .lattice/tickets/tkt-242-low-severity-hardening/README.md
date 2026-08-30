# tkt-242 — low-severity hardening batch

> **Status:** open · kind bug · priority P3 · post-merge dev→main review follow-up

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | bug | |
| priority | P3 | |
| labels | bug,P3 | |
| github | https://github.com/percena/lattice/issues/242 | |
| status | open | |
| summary | See issue #242 body for full confirmed findings + recommended fixes (file:line, failure scenarios). | |
| spec | (none — ticket-only) | post-merge review follow-up, no Spec parent |
| covers | (none — ticket-only) | |
| blocked_by | (none) | no inter-ticket deps; disjoint paths |
| parallel_group | review-fixes | all 8 tickets, disjoint paths, single layer |
| paths | skills/_lattice-lib/scripts/check-duplicate-work.sh, skills/batch-work/scripts/spawn-ticket-process.sh, skills/batch-work/scripts/run-process-wave.sh, skills/_lattice-lib/scripts/check-installed-skill-drift.sh, skills/_lattice-lib/scripts/finish-ledger.sh, skills/_lattice-lib/scripts/tests/ | disjoint from all sibling tickets |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-242 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T00:00:00Z | |

## Acceptance (this slice)

Implement every confirmed finding listed in issue #242 body, with the recommended fix applied. Re-run the relevant `bats` suite + `ci-local.sh` (or `--fast`) green before opening the PR. Open PR via `create-pr` targeting `dev` (base = integration branch per ADR-005; version bump deferred to dev→main). Stop at create-pr — do NOT call finish-work (batch marker active).

Full finding list (file:line + failure scenario + fix): https://github.com/percena/lattice/issues/242
