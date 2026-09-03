# tkt-236 — ci-gate merge-safety over-waiver

> **Status:** open · kind bug · priority P1 · post-merge dev→main review follow-up

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | bug | |
| priority | P1 | |
| labels | bug,P1 | |
| github | https://github.com/percena/lattice/issues/236 | |
| status | closed | |
| summary | See issue #236 body for full confirmed findings + recommended fixes (file:line, failure scenarios). | |
| spec | (none — ticket-only) | post-merge review follow-up, no Spec parent |
| covers | (none — ticket-only) | |
| blocked_by | (none) | no inter-ticket deps; disjoint paths |
| parallel_group | review-fixes | all 8 tickets, disjoint paths, single layer |
| paths | skills/finish-work/scripts/ci-gate-check.sh, skills/finish-work/scripts/lib/ci_failure_classify.py, skills/finish-work/scripts/tests/ | disjoint from all sibling tickets |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-236 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T10:26:20Z | |

## Acceptance (this slice)

Implement every confirmed finding listed in issue #236 body, with the recommended fix applied. Re-run the relevant `bats` suite + `ci-local.sh` (or `--fast`) green before opening the PR. Open PR via `create-pr` targeting `dev` (base = integration branch per ADR-005; version bump deferred to dev→main). Stop at create-pr — do NOT call finish-work (batch marker active).

Full finding list (file:line + failure scenario + fix): https://github.com/percena/lattice/issues/236

## Finish

- pr-244 merged: 2026-08-30T10:25:30Z — https://github.com/percena/lattice/pull/244 (base merge)
- issue #236 closed: 2026-08-30T10:25:36Z — https://github.com/percena/lattice/issues/236
