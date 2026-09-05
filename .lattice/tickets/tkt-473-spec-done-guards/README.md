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
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-04T05:03:41Z |
| updated | 2026-09-05T05:04:16Z |
| adopted | false |
| summary | Guarded Spec locked→done/superseded transitions; authoritative child-set closure; soak attestation; Spec ledger |
| spec | spc-475 — Review follow-up round 2 (path: ../../specs/spc-475-review-followup-r2.md) |
| covers | A21, A22, A23, A24, A25 |
| blocked_by | tkt-472 |
| merge_blocked_by | (none) |
| parallel_group | serial (own ship slot — #472 merged PR #478, shared-ship plan void) |
| paths | skills/_lattice-lib/scripts/spec-transition.py, tools/validate-lattice-artifacts.py, skills/finish-work/** |
| solo_merge | yes — own worktree/PR (shared #472 slot no longer exists) |
| autonomy | 3 |
| **primary_ticket** | tkt-473 (this issue) |
| **related_tickets** | tkt-472 |
| **worktree_bind** | `tkt-473-spec-done-guards` |
| worktree | sibling `…/lattice.worktrees/tkt-473-spec-done-guards/` |
| prs | pr-485 — https://github.com/percena/lattice/pull/485 |

## Acceptance (this slice)

- [x] **A21** Child open, omitted historical child, missing PR, extra PR, or open Acceptance each refuses `done` without mutation. *(spec-transition.bats tests 3–6)*
- [x] **A22** Missing/invalid soak evidence or attestation not later than last child merge refuses `done`. *(spec-transition.bats tests 7–8)*
- [x] **A23** Legal done/superseded operation is replayable, idempotent, revision-bound, and crash-recoverable. *(spec-transition.bats tests 2, 9, 10, 11, 12)*
- [x] **A24** Validator catches a hand-edited done/superseded snapshot without a valid Spec ledger. *(spec-transition.bats tests 14–15; validator `spec_terminal_without_ledger` + replay snapshot match)*
- [x] **A25** finish-work invokes the API and cannot close the Spec issue after a failed transition. *(spec-transition.bats tests 16–17; `close-spec-primary.sh` + flow.md §3.6 + SKILL.md)*

## Approach

1. Create `spec-transition.py` with `done` and `superseded` subcommands reusing #472 operation envelope.
2. Check child-set closure from Spec `tickets:` and ticket lineage back-references.
3. Require soak attestation with evidence reference + timestamp validation.
4. Add Spec ledger and validator detection of direct snapshot edits.
5. Integrate into finish-work flow.

## Anticipated decisions

- Soak attestation format (structured YAML vs prose) — disposition: agent-decides (structured: evidence_ref + timestamp).

## Decision journal

- 2026-09-05 — Ship plan revised: binder planned `serial in tkt-472 ship slot` (shared worktree/PR, `solo_merge: no`), but #472 merged via PR #478 (commit e348056) before this ticket started, so the shared slot no longer exists. #472 blocker is cleared. tkt-473 now ships in its own worktree `tkt-473-spec-done-guards` + own PR (`solo_merge: yes`). Agent-decided (autonomy 3): the alternative (reopening #472's branch) is impossible post-merge.
