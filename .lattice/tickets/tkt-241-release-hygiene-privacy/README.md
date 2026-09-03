# tkt-241 — release hygiene (privacy leak + CHANGELOG coherence)

> **Status:** open · kind bug · priority P2 · post-merge dev→main review follow-up

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | bug | |
| priority | P2 | |
| labels | bug,P2 | |
| github | https://github.com/percena/lattice/issues/241 | |
| status | closed | |
| summary | See issue #241 body for full confirmed findings + recommended fixes (file:line, failure scenarios). | |
| spec | (none — ticket-only) | post-merge review follow-up, no Spec parent |
| covers | (none — ticket-only) | |
| blocked_by | (none) | no inter-ticket deps; disjoint paths |
| parallel_group | review-fixes | all 8 tickets, disjoint paths, single layer |
| paths | .lattice/tickets/tkt-211-verify-after-mutate/README.md, .lattice/tickets/tkt-213-python3-friendly-guard/README.md, CHANGELOG.md, plugins/lattice/.claude-plugin/plugin.json | disjoint from all sibling tickets |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-241 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T10:54:16Z | |

## Acceptance (this slice)

Implement every confirmed finding listed in issue #241 body, with the recommended fix applied. Re-run the relevant `bats` suite + `ci-local.sh` (or `--fast`) green before opening the PR. Open PR via `create-pr` targeting `dev` (base = integration branch per ADR-005; version bump deferred to dev→main). Stop at create-pr — do NOT call finish-work (batch marker active).

Full finding list (file:line + failure scenario + fix): https://github.com/percena/lattice/issues/241

## Finish

- pr-250 merged: 2026-08-30T10:53:45Z — https://github.com/percena/lattice/pull/250 (base merge)
- issue #241 closed: 2026-08-30T10:53:50Z — https://github.com/percena/lattice/issues/241
