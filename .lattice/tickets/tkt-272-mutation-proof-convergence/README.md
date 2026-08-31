# tkt-272 — Mutation proof convergence for multi-PR finish

> **TL;DR:** Use one target-bound expected-OID proof contract for create, push, single-PR merge, and multi-PR merge before cleanup.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-270 → tkt-272 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/272 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-08-31T10:07:37Z |
| adopted | false |
| summary | Converge normal, delegated, batch, single-PR, and multi-PR mutation proof on target-bound expected-OID checks. |
| spec | spc-270 — workflow proof closure follow-up (path: ../../specs/spc-270-workflow-proof-closure-followup.md) |
| covers | A4 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | proof-wave-1 |
| paths | skills/_lattice-lib/scripts/verify-mutation.sh, skills/create-pr/**, skills/finish-work/scripts/verify-main-chain.sh, skills/finish-work/scripts/tests/**, skills/finish-work/references/flow.md, skills/finish-work/SKILL.md |
| solo_merge | yes |
| **primary_ticket** | tkt-272 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-272-mutation-proof-convergence` |
| worktree | sibling `…/lattice.worktrees/tkt-272-mutation-proof-convergence/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A4.1** Normal, delegated, batch, single-PR, and multi-PR paths invoke one expected-OID proof contract.
- [ ] **A4.2** Push proves remote OID; PR create proves repository/base/head/body/head OID.
- [ ] **A4.3** Merge proves the target PR is MERGED and its merge commit/content is reachable from the intended base before cleanup or ledger writes.
- [ ] **A4.4** Concurrent unrelated base advancement, wrong PR state, wrong target, and OID drift fail closed with structured recovery state.
- [ ] **A4.5** Multi-PR regression fixtures cover successful merged PR, unrelated base advancement, and stale OID.

## Approach

Extend the existing main-chain verifier instead of introducing another proof surface. Bind merge verification to the intended PR and base, not merely “base tip changed,” and replace the multi-PR OPEN-only probe with the same stage contract used by the single-PR path. Keep proof before cleanup and Finish ledger mutation. Reuse repository identity and exact-OID rules already enforced by cleanup. Add deterministic gh/git fakes for concurrent advancement and wrong-target cases.

## Anticipated decisions

- Base advancement alone is insufficient proof — disposition: pre-resolved(spc-270 A4).
- A target PR merge commit or equivalent content reachability proof is required — disposition: pre-resolved(rev-20260831-073033Z F4).
- Preserve existing cleanup exact-OID leases as a separate post-proof safety layer — disposition: pre-resolved(existing finish-work policy).
- Exact JSON recovery fields may follow existing verifier conventions — disposition: agent-decides.

## Decision journal

- 2026-08-31 — execute before coordinator integration so A3 consumes the final proof contract (source: ship-plan path independence).

## Pending decisions

(none)

## Attempts

(none)

## Notes

This ticket owns mutation proof only; coordinator persistence/integration belongs to tkt-275.

## References

- Review: `rev-20260831-073033Z`
- Spec: `spc-270`
- Prior delivery: `tkt-256`

## Lineage

- Parent spec: **spc-270**
- Parent issue: **#270**
- Primary ticket: **tkt-272**
- Related / sub-tickets: none
- Covers: **A4**
- Blocked by: none
- Merge blocked by: none
- Parallel group: proof-wave-1
- Worktree bind: `tkt-272-mutation-proof-convergence`
- Child PRs: none

## Finish

- (none yet)
