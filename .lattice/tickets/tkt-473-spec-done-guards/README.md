# tkt-473-spec-done-guards

> **TL;DR:** Replace manual Spec `locked → done` edits with a guarded, replayable transition using the M2 operation envelope.
> **Kind:** feat · **Priority:** P1
> **Path:** spc-475 → tkt-473 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/473 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-04T05:03:41Z |
| updated | 2026-09-04 |
| adopted | false |
| summary | Guarded Spec locked→done/superseded transitions; authoritative child-set closure; soak attestation; Spec ledger |
| spec | spc-475 — Review follow-up round 2 (path: ../../specs/spc-475-review-followup-r2.md) |
| covers | A21, A22, A23, A24, A25 |
| blocked_by | tkt-472 |
| merge_blocked_by | (none) |
| parallel_group | serial in tkt-472 ship slot |
| paths | skills/_lattice-lib/scripts/spec-transition.py, tools/validate-lattice-artifacts.py, skills/finish-work/** |
| solo_merge | no — ships in the #472 worktree/PR |
| autonomy | 3 |
| **primary_ticket** | tkt-473 (this issue) |
| **related_tickets** | tkt-472 |
| **worktree_bind** | `tkt-472-crash-recoverable-transitions` (shared) |
| worktree | sibling `…/lattice.worktrees/tkt-472-crash-recoverable-transitions/` |
| prs | (pending — ships with tkt-472 PR) |

## Acceptance (this slice)

- [ ] **A21** Child open, omitted historical child, missing PR, extra PR, or open Acceptance each refuses `done` without mutation.
- [ ] **A22** Missing/invalid soak evidence or attestation not later than last child merge refuses `done`.
- [ ] **A23** Legal done/superseded operation is replayable, idempotent, revision-bound, and crash-recoverable.
- [ ] **A24** Validator catches a hand-edited done/superseded snapshot without a valid Spec ledger.
- [ ] **A25** finish-work invokes the API and cannot close the Spec issue after a failed transition.

## Approach

1. Create `spec-transition.py` with `done` and `superseded` subcommands reusing #472 operation envelope.
2. Check child-set closure from Spec `tickets:` and ticket lineage back-references.
3. Require soak attestation with evidence reference + timestamp validation.
4. Add Spec ledger and validator detection of direct snapshot edits.
5. Integrate into finish-work flow.

## Anticipated decisions

- Soak attestation format (structured YAML vs prose) — disposition: agent-decides (structured: evidence_ref + timestamp).

## Decision journal

<!-- Append-only during execution. -->
