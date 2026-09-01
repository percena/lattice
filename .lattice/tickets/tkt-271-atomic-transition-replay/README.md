# tkt-271 — Atomic transition mutation and replay completeness

> **TL;DR:** Make the versioned transition contract the atomic mutation chokepoint for every M2 writer and prove replay completeness.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-270 → tkt-271 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/271 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-09-01T03:21:23Z |
| adopted | false |
| summary | Atomically mutate binder state and ledger through one guarded transition API; replay real continuity and final snapshot. |
| spec | spc-270 — workflow proof closure follow-up (path: ../../specs/spc-270-workflow-proof-closure-followup.md) |
| covers | A1 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | foundation |
| paths | skills/_lattice-lib/scripts/transition-api.py, skills/_lattice-lib/scripts/lib/transition_table.py, skills/_lattice-lib/scripts/lib/status_vocab.py, skills/_lattice-lib/scripts/{finish-ledger,bump-fix-cycle,ratify,spec-supersede,stamp-pr-open,reconcile-state}.sh, skills/_lattice-lib/scripts/tests/**, docs/workflow-fsm.md, tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-271 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-271-atomic-transition-replay` |
| worktree | sibling `…/lattice.worktrees/tkt-271-atomic-transition-replay/` |
| prs | pr-296 — https://github.com/percena/lattice/pull/296 |

## Acceptance (this slice)

- [x] **A1.1** One API locks the binder, reads the real prior status/coupled fields, validates the versioned edge, and atomically writes status/wait_reason/updated plus one ticket-bound ledger entry. — `transition-api.py commit`: dir-flock → read prior status/wait_reason → edge + escape + coupled wait_reason validation → temp binder + ledger append + atomic `os.replace`; proven by `transition-api.bats` #10/#14.
- [x] **A1.2** Validation, ledger, or binder-write failure leaves neither partial state nor a misleading transition record. — fail-close ordering (validate → temp → ledger → rename) + `_rollback_ledger` on rename failure; proven by fault-injection `transition-api.bats` #18 (chmod 000 ledger dir → exit 3, binder byte-identical, no temp residue, no ledger growth).
- [x] **A1.3** All production M2 writers use the guarded API while preserving existing CLI and human-adjudicated escape semantics. — increment 2 routed the 5 status-writers through `commit`: stamp-pr-open, finish-ledger, ratify, spec-supersede, bump-fix-cycle (status flip + journal trace + `updated` + ledger in one `commit` transaction; each CLI/escape preserved). `record` retained as the ledger-only primitive (test/non-canonical + the one-time historical backfill below). reconcile-state.sh is read-only (pure drift detector) — no status path to migrate; its suite is a regression gate. The 6 dev-base drift ledgers (tkt-256/261/284/285/286/287 — finish-ledger closed without recording pr-open→closed) were backfilled via `record` so ledger final `to`=closed reconciles with binder. Green: stamp-pr-open 27, finish-ledger 50, ratify 20, spec-supersede 13, bump-fix-cycle 17, reconcile-state 31.
- [x] **A1.4** Replay rejects discontinuity, wrong ticket identity, illegal/omitted transitions, and final ledger-to-binder snapshot mismatch. — `replay-ledger` strengthened with identity/continuity/snapshot invariants; proven by `transition-api.bats` #19/#20/#21/#22. The validator's inline replay now enforces the same three (A1.5).
- [x] **A1.5** Schema↔FSM parity covers owner, guard, reason, escape, trace, and metric; drift fails CI. — `transition-parity.bats` asserts lib↔validator FULL field-equality (owner/guard/reason/escape/trace/metric/escape_required via a vendored `LEGAL_EDGES_FULL`), projection consistency, and lib↔docs Owner parity per documented M2 edge. The validator's inline replay now enforces identity/continuity/snapshot (migration posture: the 6 drift ledgers backfilled FIRST so CI stays green; snapshot is a hard error going forward). Proven by `transition-parity.bats` 8/8 + `transition-api.bats` validator-replay tests.

## Approach

Extend `transition-api.py` from append-only recording into a binder-bound transaction with an exclusive lock and typed coupled-field patch. Keep the versioned table as the edge source of truth, then migrate each existing status writer behind a compatibility call rather than rewriting its public CLI. Replay each ticket stream in order, check identity and continuity, and compare the final `to` plus coupled fields with the current binder. Add per-writer regression and injected-failure fixtures before switching canonical callers. Touch only shared transition/writer surfaces; batch process and coordinator code consume this API in later tickets.

## Anticipated decisions

- Transaction boundary includes binder mutation and ledger append — disposition: pre-resolved(spc-270 A1).
- Git remains durable history, but replay requires complete per-ticket transition records — disposition: pre-resolved(rev-20260831-073033Z).
- Compatibility shims may preserve writer CLIs during migration — disposition: agent-decides, provided no bypass remains in canonical paths.
- Escape-required side-state transitions remain human-adjudicated — disposition: pre-resolved(ADR-007 / spc-270 D1).

## Decision journal

- 2026-08-31 — foundation runs before process/coordinator slices to avoid duplicate state mutation semantics (source: spc-270 D2).
- 2026-08-31 — increment 1 delivered: atomic `commit` + replay identity/continuity/snapshot invariants + fault-injection fixtures. `record` kept as the ledger-only primitive so non-canonical/test callers and the not-yet-migrated writers keep working; `commit` is the canonical path writers will route to in increment 2 (A1.3). No bypass is introduced — `commit` enforces edge+escape+coupled-field; `record` does not mutate the binder, so a writer that only calls `record` leaves the binder status row untouched (replay's snapshot check would flag any drift). Source: spc-270 A1 Approach ("add fixtures before switching canonical callers").
- 2026-09-01 — increment 2 delivered: A1.3 + A1.5. `commit` gained `--append-journal` so a writer's structured Decision-journal trace lands in the SAME atomic transaction as the status flip + `updated` + ledger (a crash before `commit` leaves no trace → re-run appends it once, no duplicate). The 5 status-writers route status+journal+updated+ledger through `commit`; each keeps its non-status field mutations (prs/## Finish/fix_cycles/wait_reason row) in its own python heredoc. Schema gap surfaced + closed: spec-supersede stamps `in-progress → deferred` (an in-flight child) and `deferred → deferred` (reason-supersede self-loop, analogous to `pr-open → pr-open` rebase-void) — both were absent from `LEGAL_EDGES`, so `commit` would have rejected them; added to lib+validator+docs in parity. bump-fix-cycle's `pr-open → rework` flip goes through `commit`; the `rework → rework` --extend-budget escape (no real status flip, not a legal edge) keeps the original single in-python write (fix_cycles + journal, no `commit`). Tradeoff (fail-safe): a crash between bump-fix-cycle's fix_cycles write and `commit` could double-increment fix_cycles on re-run — but this over-counts → hits the ≤2 cap → forces deep-review (human), the conservative failure mode. reconcile-state.sh confirmed read-only (no status path to migrate). A1.5 validator inline replay got identity/continuity/snapshot; migration posture = backfill the 6 dev-base drift ledgers (tkt-256/261/284/285/286/287, missing pr-open→closed) via `record` (the historical-repair use case that justifies keeping `record`) BEFORE enabling snapshot as a hard error, so CI stays green.
- 2026-09-01 — red-run disposition (finish-work DEFAULT 15):
  - lattice-scripts runs 33465409182 + 33465918969 FAILED — REAL: bare `! grep -q` assertion at transition-api.bats:182 (increment-1) flagged by the repo guard corpus. Fixed in ebd25eb (effective `if grep -q; then false; fi`); latest lattice-scripts run 33466351091 SUCCESS.
  - artifacts runs 33465918956 + 33466351066 FAILED — pre-existing spec drift (spc-277 done/unchecked-acceptance + spec header mismatch; spc-282 prs union), 0 transition-ledger findings. Out-of-paths; ticketed #300; not a tkt-271 regression.

## Pending decisions

(none)

## Attempts

(none)

## Notes

Foundation is intentionally serial. A2/A3 tickets may call the resulting API but must not redefine transition semantics.

Increment 1 (this commit) lands the atomic `commit` transaction + the strengthened replay invariants + fault-injection fixtures; A1.1/A1.2/A1.4 are proven. Increment 2 (delivered 2026-09-01): migrated the 5 M2 status-writers behind `commit` (A1.3) and asserted field-level schema↔FSM parity (A1.5). No `record`/direct-stamp bypass remains in a canonical writer status path.

Replay invariant surfaced 6 pre-existing dev-base drift cases (tkt-256/261/284/285/286/287): ledger final `to`=pr-open but binder `status`=closed — finish-ledger closed the binder without recording a `pr-open -> closed` ledger entry (the exact bypass A1.3 cures). Disposition (delivered): increment 2 migrated finish-ledger to `commit` (records the close flip going forward) AND backfilled the 6 historical ledgers with their missing `pr-open -> closed` entry via `record` (the historical-repair use case), so the ledger final `to`=closed reconciles with binder `status`=closed. `replay-ledger` on the 8 tracked ledgers: 14 entries, 0 illegal/inconsistent.

- NOTICED: `skills/_lattice-lib/scripts/tests/{stamp-pr-open,ratify,bump-fix-cycle,spec-supersede}.bats` write a real `.lattice/.transition-ledger/tkt-7.jsonl`/`tkt-9.jsonl` into the repo home (not a tmp dir) and leave it as untracked residue after a suite run — out-of-paths test hygiene, 2026-08-31. Not folded into this slice; a later sweep ticket is the disposition. (These are removed from the working tree before commit; they are untracked and never ship.)
- NOTICED: `tools/ci-local.sh --fast` `lattice-artifacts` step FAILs on the dev base — pre-existing spec drift unrelated to this slice: spc-277 (status=done but Acceptance boxes A1-A6 unchecked) + spc-282 (spec `prs` omits the child PR union) + a spec-header status mismatch. 0 transition-ledger findings (the backfill reconciled). Out-of-paths (`.lattice/specs/spc-27[78]*`), 2026-09-01; a later spec-hygiene sweep is the disposition, not this agent's detour.

- NOTICED: `skills/_lattice-lib/scripts/tests/{stamp-pr-open,ratify,bump-fix-cycle}.bats` write a real `.lattice/.transition-ledger/tkt-7.jsonl` into the repo home (not a tmp dir) and leave it as untracked residue after a suite run — out-of-paths test hygiene, 2026-08-31. Not folded into this slice; a later sweep ticket is the disposition.

## References

- Review: `rev-20260831-073033Z`
- Spec: `spc-270`
- Prior delivery: `tkt-255` / `spc-254`
- PR: `pr-296`
- Follow-up tickets (surfaced by the pr-296 review):
  - #297 — two-write atomicity refactor (`prepare_commit_text`); cures bump-fix-cycle double-increment + writer concurrency windows.
  - #298 — migrate batch-work coordinator from `record` to `commit` (A1.5 snapshot check flags batch-work until done).
  - #299 — test-residue hygiene (writer bats write tkt-7/tkt-9 ledgers into repo home).
  - #300 — spec drift sweep (spc-277 unchecked acceptance + spc-282 prs union; pre-existing ci-local FAIL).

## Lineage

- Parent spec: **spc-270**
- Parent issue: **#270**
- Primary ticket: **tkt-271**
- Related / sub-tickets: none
- Covers: **A1**
- Blocked by: none
- Merge blocked by: none
- Parallel group: foundation
- Worktree bind: `tkt-271-atomic-transition-replay`
- Child PRs: none

## Finish

- (none yet)
