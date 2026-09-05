---
id: spc-475
slug: review-followup-r2
title: "Review follow-up round 2 — recoverable workflow engine"
kind: fix
status: done
mode: C
priority: P0
summary: "Protected-branch finish repair, recoverable batch coordinator, crash-recoverable transitions, Spec done guards, FSM docs closure"
created: 2026-09-04
updated: 2026-09-05
tickets: [tkt-470, tkt-471, tkt-472, tkt-473, tkt-474]
prs: [pr-476, pr-477, pr-478, pr-485]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Review follow-up round 2 — recoverable workflow engine

> **TL;DR:** Six findings from the 2026-09-04 review (rev-20260904-043350Z) expose crash/recovery gaps in the finish-stamp CI, batch coordinator, M2 transition API, and Spec lifecycle — fix them and close the FSM documentation gap.
> **Kind:** fix · **Status:** done · **Mode:** C · **Priority:** P0
> **Path:** spc-475 → tkt-470..474 → (pr-…)

## Why

The 2026-09-04 full-repo review (rev-20260904-043350Z) verified six findings that spc-458 did not cover. Two are P0 bugs: (1) the GHA finish-stamp safety net cannot independently land a repair on protected `dev` because its direct-push approach fails required checks; (2) the batch coordinator does not persist future waves, so a host restart loses them. The remaining findings are P1/P2 improvements to crash recovery, Spec lifecycle guards, and FSM documentation.

## In scope

- tkt-470: Replace direct protected-base push with an idempotent repair branch/PR protocol; aggregate child stamp failures; postcondition verification on staged-empty.
- tkt-471: Persist complete versioned DAG before spawn; resume driver; CAS/monotonic cursor; idempotent terminal transitions; fault tests.
- tkt-472: Stable operation_id + revision; durable prepared/committed/recovery protocol with fsync; SIGKILL recovery; retryable finish staging; ledger event contracts.
- tkt-473: Guarded Spec `locked → done` / `locked → superseded` transitions; authoritative child-set closure; soak attestation; Spec ledger (ships in #472 worktree).
- tkt-474: FSM document reconciliation; parity CI path filter; contract test (ships in #472 worktree).

## Out of scope

- Replacing the local-primary finish path
- Database/workflow-service migration
- Historical rewrite of legacy ledgers or clearing the warning baseline
- Automatically deciding dogfood soak criteria
- General-purpose workflow engine or remote cross-clone coordinator

## Acceptance

- [x] **A1** Missing local stamp creates or updates one deterministic repair PR targeting the merged PR base; no direct push to protected `dev`.
- [x] **A2** Any child stamp failure produces final non-zero even when nothing is staged.
- [x] **A3** Staged-empty returns success only after per-binder postcondition verification.
- [x] **A4** Repeated dispatch is idempotent and already-repaired state is a clean no-op.
- [x] **A5** PR create/update, validator, and publication failures are fail-loud.
- [x] **A6** Focused Bats cover first repair, repeated repair, child failure aggregation, inconsistent empty-stage, and consistent race resolution.
- [x] **A7** Complete future layers/waves are durable before the first worker starts; plan hash/revision identifies the execution plan.
- [x] **A8** Restart between waves returns the real next unspawned node and a production driver can continue it.
- [x] **A9** Init/load failure prevents spawn; canonical record/cursor persistence failures cannot be warning-only success.
- [x] **A10** Stale marker/node writes cannot regress a cursor already advanced to a later tuple.
- [x] **A11** Replaying the same failed/timeout/unknown command returns already-applied success and emits one binder transition.
- [x] **A12** Transition failure remains retryable and never marks the node settled prematurely.
- [x] **A13** Multi-process fault tests cover stale writers, terminal replay, pre-spawn restart, and reservation recovery.
- [x] **A14** Duplicate submission of one operation is an idempotent success with one event.
- [x] **A15** Expected-revision mismatch fails before mutation.
- [x] **A16** SIGKILL after temp, after ledger append, before rename, and after rename is recovered to a consistent snapshot on rerun.
- [x] **A17** Finish git-add/index failure returns `needs-stage`; rerun stages existing consistent files instead of early no-op.
- [x] **A18** Writer and validator reject invalid owner/reason-code, missing required trace/metric, and revision discontinuity.
- [x] **A19** Post-cutoff active/terminal binders require an anchor or explicit migration marker; legacy fixtures remain ratcheted warnings.
- [x] **A20** Bare ordinary `record` cannot fabricate an event detached from binder revision.
- [x] **A21** Child open, omitted historical child, missing PR, extra PR, or open Acceptance each refuses `done` without mutation.
- [x] **A22** Missing/invalid soak evidence or attestation not later than last child merge refuses `done`.
- [x] **A23** Legal done/superseded operation is replayable, idempotent, revision-bound, and crash-recoverable.
- [x] **A24** Validator catches a hand-edited done/superseded snapshot without a valid Spec ledger.
- [x] **A25** finish-work invokes the API and cannot close the Spec issue after a failed transition.
- [x] **A26** Documentation accurately describes actual transition replay and no longer claims history is not replayed.
- [x] **A27** Documentation describes the final protected-branch repair, durable coordinator, recoverable operation, and guarded Spec semantics without overclaiming.
- [x] **A28** A docs-only change to `docs/workflow-fsm.md` triggers the `bats` workflow.
- [x] **A29** Schema/docs single-sided changes fail parity.
- [x] **A30** Static regression test fails if the parity document path disappears from workflow filters.

## Non-goals

- Replacing the model-driven parts of start-work/batch-work with scripts wholesale
- Making L1/L3 hooks honour `LATTICE_HOOK_MODE` (policy change; operator decision)
- Lock timeouts / directory-flock portability extraction

## Decisions (principal, user-confirmed)

1. **Scope = confirmed findings only, delivered through the standard pipeline.** Serial single-worktree per solo-merge ticket (#470, #471); #472 is the primary ship slot for serial #473 and #474.
2. **Parallel group G1 with solo-merge** — all three independent tickets (#470, #471, #472) can be worked in parallel but merge one at a time.

## Agent-assumed (secondary)

- Repair PR protocol (#470) uses a deterministic branch name (`lattice/finish-repair/<base>`) so repeated dispatch updates the same PR.
- Coordinator DAG (#471) is persisted as JSON with a plan hash for identity.
- Operation envelope (#472) uses file-based prepared/committed protocol with directory fsync.
- Spec done guard (#473) reuses the #472 operation/revision/recovery envelope.

## Risks / open questions

- The three independent tracks (#470, #471, #472) touch disjoint file sets but all target `dev`; merge order is solo-merge (one at a time).
- #473 and #474 are blocked by #472; they ship in the same PR.

## References

- Review: `rev-20260904-043350Z`
- Prior Spec: `spc-458` (review follow-up round 1), `spc-416` (post-merge ledger stamping), `spc-254` (executable workflow contracts), `spc-270` (workflow proof closure)
- ADR: ADR-012, ADR-013

## Links / bloodline (L0)

- Primary: [#475](https://github.com/percena/lattice/issues/475)
- Tickets: tkt-470, tkt-471, tkt-472, tkt-473, tkt-474
- PRs: (pending)
- Reviews: (none)
