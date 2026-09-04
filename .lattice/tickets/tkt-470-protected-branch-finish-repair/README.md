# tkt-470-protected-branch-finish-repair

> **TL;DR:** Replace the GHA finish-stamp's direct push with a repair-branch/PR protocol that survives branch protection.
> **Kind:** fix · **Priority:** P0
> **Path:** spc-475 → tkt-470 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P0 |
| labels | bug, github_actions, P0 |
| github | https://github.com/percena/lattice/issues/470 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-04T05:02:59Z |
| updated | 2026-09-04 |
| adopted | false |
| summary | Replace direct protected-base push with idempotent repair branch/PR protocol; aggregate child failures; postcondition verification |
| spec | spc-475 — Review follow-up round 2 (path: ../../specs/spc-475-review-followup-r2.md) |
| covers | A1, A2, A3, A4, A5, A6 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | .github/workflows/finish-stamp.yml, skills/_lattice-lib/scripts/finish-stamp-ci.py, skills/_lattice-lib/scripts/tests/finish-stamp-ci.bats |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-470 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-470-protected-branch-finish-repair` |
| worktree | sibling `…/lattice.worktrees/tkt-470-protected-branch-finish-repair/` |
| prs | (pending) |

## Acceptance (this slice)

- [ ] **A1** Missing local stamp creates or updates one deterministic repair PR targeting the merged PR base; no direct push to protected `dev`.
- [ ] **A2** Any child stamp failure produces final non-zero even when nothing is staged.
- [ ] **A3** Staged-empty returns success only after per-binder postcondition verification.
- [ ] **A4** Repeated dispatch is idempotent and already-repaired state is a clean no-op.
- [ ] **A5** PR create/update, validator, and publication failures are fail-loud.
- [ ] **A6** Focused Bats cover first repair, repeated repair, child failure aggregation, inconsistent empty-stage, and consistent race resolution.

## Approach

1. Modify `finish-stamp-ci.py` to detect when a direct push to the protected base fails.
2. On failure, create/update a deterministic repair branch (`lattice/finish-repair/<base>`) with the stamp commit.
3. Create or update a PR from the repair branch to the base, using `gh pr create`/`gh pr edit`.
4. Aggregate all child binder stamp/re-stamp failures into a single exit code.
5. On staged-empty, verify per-binder postconditions (Finish record, transition ledger, snapshot consistency) before returning success.
6. Handle idempotent repeated dispatch: if the repair branch already matches the target state, no-op.
7. Add focused Bats tests covering all acceptance criteria.

## Anticipated decisions

- Repair branch naming convention (`lattice/finish-repair/<base>` vs per-PR) — disposition: agent-decides (reversible; per-base is simpler and idempotent).
- Whether to use `gh pr create` or the API directly — disposition: agent-decides (gh CLI is sufficient and consistent with project conventions).

## Decision journal

<!-- Append-only during execution. -->
