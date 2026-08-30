# tkt-243 — review-skill release-boundary merge-review mode

> **Status:** open · kind enhancement · priority P2 · post-merge dev→main review follow-up

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | enhancement | |
| priority | P2 | |
| labels | enhancement,P2 | |
| github | https://github.com/percena/lattice/issues/243 | |
| status | closed | |
| summary | See issue #243 body for full confirmed findings + recommended fixes (file:line, failure scenarios). | |
| spec | (none — ticket-only) | post-merge review follow-up, no Spec parent |
| covers | (none — ticket-only) | |
| blocked_by | (none) | no inter-ticket deps; disjoint paths |
| parallel_group | review-fixes | all 8 tickets, disjoint paths, single layer |
| paths | skills/review-code/SKILL.md, skills/review-code/references/policy.md, skills/review-production/SKILL.md, skills/review-production/references/policy.md, docs/adr/ | disjoint from all sibling tickets |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-243 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T11:08:14Z | |

## Acceptance (this slice)

Implement every confirmed finding listed in issue #243 body, with the recommended fix applied. Re-run the relevant `bats` suite + `ci-local.sh` (or `--fast`) green before opening the PR. Open PR via `create-pr` targeting `dev` (base = integration branch per ADR-005; version bump deferred to dev→main). Stop at create-pr — do NOT call finish-work (batch marker active).

Full finding list (file:line + failure scenario + fix): https://github.com/percena/lattice/issues/243

## Finish

- pr-252 merged: 2026-08-30T11:07:49Z — https://github.com/percena/lattice/pull/252 (base merge)
- issue #243 closed: 2026-08-30T11:07:55Z — https://github.com/percena/lattice/issues/243
