# tkt-472-crash-recoverable-transitions

> **TL;DR:** Give M2 mutations stable operation identity, crash recovery, retryable finish staging, and enforceable ledger contracts.
> **Kind:** feat · **Priority:** P1
> **Path:** spc-475 → tkt-472 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/472 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-04T05:03:24Z |
| updated | 2026-09-04 |
| adopted | false |
| summary | Stable operation_id + revision; durable prepared/committed/recovery protocol; SIGKILL recovery; retryable finish staging; ledger contracts |
| spec | spc-475 — Review follow-up round 2 (path: ../../specs/spc-475-review-followup-r2.md) |
| covers | A14, A15, A16, A17, A18, A19, A20 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/transition-api.py, skills/_lattice-lib/scripts/finish-stamp.py, skills/_lattice-lib/scripts/ensure-workspace.sh, tools/validate-lattice-artifacts.py |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-472 (this issue) |
| **related_tickets** | tkt-473, tkt-474 |
| **worktree_bind** | `tkt-472-crash-recoverable-transitions` |
| worktree | sibling `…/lattice.worktrees/tkt-472-crash-recoverable-transitions/` |
| prs | (pending) |

## Acceptance (this slice)

- [ ] **A14** Duplicate submission of one operation is an idempotent success with one event.
- [ ] **A15** Expected-revision mismatch fails before mutation.
- [ ] **A16** SIGKILL after temp, after ledger append, before rename, and after rename is recovered to a consistent snapshot on rerun.
- [ ] **A17** Finish git-add/index failure returns `needs-stage`; rerun stages existing consistent files instead of early no-op.
- [ ] **A18** Writer and validator reject invalid owner/reason-code, missing required trace/metric, and revision discontinuity.
- [ ] **A19** Post-cutoff active/terminal binders require an anchor or explicit migration marker; legacy fixtures remain ratcheted warnings.
- [ ] **A20** Bare ordinary `record` cannot fabricate an event detached from binder revision.

## Approach

1. Add `operation_id` (UUID) + `expected_revision` params to transition-api.py mutations.
2. Implement prepared/committed protocol: write temp → fsync → append ledger → fsync dir → rename.
3. Recovery on startup: scan for `.transition-api.*.prepared` files and resolve them.
4. Make finish staging durable: `needs-stage` state survives rerun.
5. Add ledger event contract validation to the writer and validator.
6. Bats tests use real subprocess crash points.

## Anticipated decisions

- Prepared file naming convention — disposition: agent-decides (`.transition-api.<op_id>.prepared`).
- Legacy ratchet cutoff date — disposition: must-ask (policy decision).

## Decision journal

<!-- Append-only during execution. -->
