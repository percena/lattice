# tkt-152-state-reconcile

> **TL;DR:** Add a read-only, repository-bound GitHub-to-binder reconciliation check for interrupted workflow recovery.
> **Kind:** feat · **Priority:** P2
> **Path:** rev-20260828-082751Z → tkt-152 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/152 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | Detect cross-system GitHub and binder drift without mutating either source |
| spec | (none — ticket-only) |
| covers | A1, A2, A3, A4, A5 |
| blocked_by | #150, #151 |
| parallel_group | G2 |
| paths | skills/_lattice-lib/scripts/reconcile-state.sh; skills/_lattice-lib/scripts/tests/reconcile-state.bats; docs/morning-triage.md; skills/finish-work/references/flow.md; tools/ci-local.sh (only if a credential-free mode is wired) |
| solo_merge | yes after blockers land |
| **primary_ticket** | tkt-152 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-152-state-reconcile` |
| worktree | sibling `…/lattice.worktrees/tkt-152-state-reconcile/` |
| prs | (none) |

## Acceptance

- [ ] **A1** Reconciled fixtures return `ok:true`; each drift class returns `ok:false` with stable reason codes and affected ids.
- [ ] **A2** GitHub unavailable/unauthorized is `unknown` and nonzero, never a false clean result.
- [ ] **A3** The helper is read-only and repository-identity-bound; tests prove it performs no GitHub or binder mutation.
- [ ] **A4** Morning triage and finish recovery docs name the check and manual recovery route.
- [ ] **A5** Full `bash tools/ci-local.sh` passes.

## Approach

- Implement a standalone read-only helper beside other portable `_lattice-lib` scripts.
- Parse local binder id/status/prs/Finish evidence, query issue and referenced PR state once per id, and compare using the terminal rules landed by blockers.
- Bind every query to the binder repository identity; reject foreign or unresolved targets.
- Emit deterministic JSON and a concise human table with `ok|drift|unknown` results.
- Use fake `gh` and fixture repos for success, each drift family, auth/network unknown, and read-only assertions.
- Document use in morning triage and interrupted finish recovery; do not auto-repair.

## Anticipated decisions

- Helper name and JSON schema — disposition: agent-decides; follow sibling helper conventions and stable reason-code patterns.
- CI integration — disposition: agent-decides; default to an explicit operator/recovery check unless live GitHub credentials are intentionally available.

## Decision journal

## Pending decisions

## Attempts

## Notes

## References

- Review: `rev-20260828-082751Z`
- Blockers: tkt-150, tkt-151

## Lineage

- Parent spec: none
- Parent issue: none
- Primary ticket: **tkt-152**
- Related tickets: none
- Covers: **A1, A2, A3, A4, A5**
- Blocked by: **tkt-150, tkt-151**
- Parallel group: G2
- Worktree bind: `tkt-152-state-reconcile`

## Finish

- (none yet)
