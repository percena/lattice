---
id: rev-20260828-082751Z
slug: fsm-analysis-second-pass
title: "FSM analysis second pass — confirmed defects, corrected severity, bounded repair set"
kind: audit
status: concluded
outcome: spawn_tickets
summary: "Second-pass verification confirms ratify, cancel, and artifact-state defects; narrows architecture recommendations"
created: 2026-08-28
updated: 2026-08-28
related_specs: []
related_tickets: [tkt-149, tkt-150, tkt-151, tkt-152]
related_prs: []
---

# Review: FSM analysis second pass

> **TL;DR:** Three executable/state-contract defects are confirmed, one cross-system recovery gap is a bounded P2 enhancement, and the proposed event-sourced FSM/M3 redesign is explicitly deferred as architecture work rather than mislabeled as a bug.
> **Kind:** audit · **Status:** concluded · **Outcome:** spawn_tickets
> **Next:** deliver tkt-149/tkt-150/tkt-151 in parallel, then tkt-152 after the terminal contracts land.

## Context

The operator asked for an independent review of the 2026-08-28 repo-wide FSM/process audit before turning its conclusions into tickets and implementation. This pass re-ran the reproductions, inspected the relevant helpers and tests, checked the current GitHub/binder state, and separated present defects from broader best-practice recommendations.

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | The core problems are real: canonical ratification fails before mutation; cancel can leave a closed issue with a working binder; the L0 validator accepts impossible Spec/Review/coupled-ticket snapshots and the current tree contains Spec terminal drift. |
| Information | Sufficient. Exact helper behavior, validator behavior, current artifacts, GitHub state, and full local CI were available. No must-have gap remains for the bounded repairs. |
| Hidden issues | `ratify.sh` has more failure modes than the first audit listed: EOF journal handling under `pipefail`, unrelated staged-file capture, no pending-decision settlement, and no contained/atomic writer. The earlier M3 criticism was too broad: review-delivery already carries a digest-based ratification ledger, though it is not a fully structured state engine. |

## Method

- Reproduced `ratify.sh` against a canonical parked binder: exit 1 with parsed status `''`.
- Reproduced closed-without-merge + closed issue from `stuck`: helper exited 0, binder remained `stuck`, validator exited 0.
- Constructed invalid Spec/Review/ticket fixtures: unknown statuses/outcomes and `stuck + wait_reason: nonsense` all passed L0 validation.
- Inspected all current Specs: `spc-116` is `done` with A1-A10 open and a stale `Status: locked`; `spc-12` and `spc-4` also retain stale locked display state.
- Compared all 66 current ticket binders to live GitHub issue/PR state: zero current mismatches.
- Ran `bash tools/ci-local.sh`: all executed checks passed; plugin-version check skipped because no bundled paths changed.
- Dropped claims that did not meet the material-defect bar: a centralized event log and fully structured M3 are future architecture choices, not required bug fixes for this repair set.

## Findings

1. **P1 — the formal `parked → queued` transition is unreachable and its writer is unsafe even after the parser is fixed.** Evidence: `skills/_lattice-lib/scripts/ratify.sh` status extraction greedily consumes the row; BSD-only `sed -i ''`; an EOF journal can abort under `set -e -o pipefail`; the script neither settles the selected pending decision nor protects against unrelated staged content. No ratify Bats suite exists. Spawn `tkt-149`.
2. **P1 — terminal cancellation is not closed over the declared working-state vocabulary.** Evidence: `finish-ledger.sh` omits `parked|stuck|deferred`; its Bats suite explicitly preserves parked despite the FSM cancel-from-any-state law; no-PR cancel lacks a supported ledger writer. Spawn `tkt-150`.
3. **P1 — artifact CI validates selected syntax but misses declared state invariants, and current artifacts already violate them.** Evidence: invalid Spec/Review/coupled-ticket fixtures pass; `spc-116` is terminal with ten open A* boxes; three Specs have frontmatter/display status disagreement. The earlier analysis slightly overstated the validator's advertised remit because its docstring says “selected, not exhaustive”; the defect is instead that declared lifecycle invariants and CI enforcement have diverged. Spawn `tkt-151`.
4. **P2 — GitHub/binder saga interruption is detectable only by manual inspection.** The current live state is clean and create/finish helpers are resumable, so this is not a present corruption incident and severity is reduced from the earlier analysis. A read-only reconciliation command is still warranted because individually valid snapshots cannot expose an interrupted cross-system sequence. Spawn `tkt-152`, blocked by terminal-contract tickets.
5. **Informational — the M3/event-sourcing recommendation is not a confirmed defect in this scope.** Review-delivery already records ratifications in digests and proposes promotion after two citations. A stable decision id/event log could improve rigor, but it changes the artifact model and needs a future Spec/ADR rather than an opportunistic bug ticket.
6. **Low, folded into tkt-151 — batch “never-spawned” wording is ambiguous, not a separate state bug.** Fuse-halted and blocked-by-failure cases are defined as `deferred`; the generic “never-spawned stays queued” sentence should be narrowed to not-selected/not-attempted cases.

## Recommendations

1. Land the planning artifacts first so every implementation worktree starts from durable binders.
2. Batch `tkt-149`, `tkt-150`, and `tkt-151` as path-disjoint G1 work; each gets a dedicated PR and independent review.
3. Land G1 only after review-code and full CI are clean, then start `tkt-152` against the stable terminal contract.
4. Treat a general transition/event API and structured M3 identifiers as a future `spawn_spec` candidate after these repairs provide evidence about the remaining operational pain.

## Outcome

`spawn_tickets` — scope is concrete and split into four self-contained delivery units.

### Follow-ups

- [x] Create tkt-149 ratify transaction repair.
- [x] Create tkt-150 terminal cancel repair.
- [x] Create tkt-151 artifact state invariants repair.
- [x] Create tkt-152 read-only reconciliation helper.

## References

- `docs/workflow-fsm.md`
- `skills/_lattice-lib/scripts/ratify.sh`
- `skills/_lattice-lib/scripts/finish-ledger.sh`
- `tools/validate-lattice-artifacts.py`
- `.lattice/specs/spc-116-retire-release-train.md`
