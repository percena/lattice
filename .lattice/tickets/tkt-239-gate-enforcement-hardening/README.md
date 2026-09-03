# tkt-239 — gate-enforcement hardening

> **Status:** open · kind bug · priority P2 · post-merge dev→main review follow-up

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | bug | |
| priority | P2 | |
| labels | bug,P2 | |
| github | https://github.com/percena/lattice/issues/239 | |
| status | closed | |
| summary | See issue #239 body for full confirmed findings + recommended fixes (file:line, failure scenarios). | |
| spec | (none — ticket-only) | post-merge review follow-up, no Spec parent |
| covers | (none — ticket-only) | |
| blocked_by | (none) | no inter-ticket deps; disjoint paths |
| parallel_group | review-fixes | all 8 tickets, disjoint paths, single layer |
| paths | plugins/lattice/hooks/intercept-shippable-write.sh, plugins/lattice/hooks/intercept-git-branch-create.sh, plugins/lattice/hooks/lib/batch-merge-gate.sh, skills/_lattice-lib/scripts/ensure-workspace.sh, skills/_lattice-lib/scripts/bump-fix-cycle.sh, skills/_lattice-lib/scripts/build-review-context.sh, tools/ci-local.sh, .github/workflows/lint-heavy.yml | disjoint from all sibling tickets |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-239 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T10:51:11Z | |

## Acceptance (this slice)

Implement every confirmed finding listed in issue #239 body, with the recommended fix applied. Re-run the relevant `bats` suite + `ci-local.sh` (or `--fast`) green before opening the PR. Open PR via `create-pr` targeting `dev` (base = integration branch per ADR-005; version bump deferred to dev→main). Stop at create-pr — do NOT call finish-work (batch marker active).

Full finding list (file:line + failure scenario + fix): https://github.com/percena/lattice/issues/239

## Finish

- pr-249 merged: 2026-08-30T10:50:43Z — https://github.com/percena/lattice/pull/249 (base merge)
- issue #239 closed: 2026-08-30T10:50:49Z — https://github.com/percena/lattice/issues/239
