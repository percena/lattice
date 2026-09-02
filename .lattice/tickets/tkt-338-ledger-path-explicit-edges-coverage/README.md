# tkt-338-ledger-path-explicit-edges-coverage

> **TL;DR:** Ledger resolved from the binder's Lattice home (not cwd), explicit terminal edges replace any→closed, closed_without_ledger coverage metric.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-337 → tkt-338 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug,P1 |
| github | https://github.com/percena/lattice/issues/338 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T02:29:15Z |
| adopted | false |
| summary | Ledger resolved from the binder's Lattice home (not cwd), explicit terminal edges replace any→closed, closed_without_ledger coverage metric. |
| spec | spc-337 — FSM conformance closure (path: ../../specs/spc-337-fsm-conformance-closure.md) |
| covers | A1, A2 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/scripts/transition-api.py, skills/_lattice-lib/scripts/lib/{transition_table,queue_health}.py, skills/_lattice-lib/scripts/{queue-health,finish-ledger,stamp-pr-open,ratify,bump-fix-cycle}.sh, skills/_lattice-lib/scripts/tests/**, tools/validate-lattice-artifacts.py, tools/.validator-warning-baseline.txt, tools/tests/**, docs/workflow-fsm.md, skills/_lattice-lib/references/workflow-fsm-reference.md |
| solo_merge | yes |
| **primary_ticket** | tkt-338 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-338-ledger-path-explicit-edges-coverage |
| worktree | sibling `…/lattice.worktrees/tkt-338-ledger-path-explicit-edges-coverage/` |
| prs | (none) |

## Acceptance (this slice)

See GitHub issue #338 for the full slice text; Spec ids owned by this slice:

- [ ] **A1** Ledger path from binder home; four writers stage the same path; fault test from non-toplevel cwd; `closed_without_ledger` (error ≥ 2026-09-02, warn before); queue-health coverage + direct-jump rows.
- [ ] **A2** No `any → closed`; explicit merge / direct-jump / cancel edges; finish-ledger merge from queued|in-progress → `reason: merge` + `direct-jump` + `anomaly:`; vendored copy + docs + parity bats agree; replay of committed ledgers green.

## Approach

1. `transition-api.py`: add `resolve_home(binder_path)` = the `.lattice` ancestor of the binder (`tickets/<dir>/README.md` → up 3); thread the home into `ledger_path()`/`lock_path()`; `prepare_commit_text`/`commit_transaction` receive the binder path (they already do) and derive the home from it; `LATTICE_HOME` env stays as explicit override only when set.
2. Four writers (`finish-ledger.sh:639`, `stamp-pr-open.sh:512`, `ratify.sh:294`, `bump-fix-cycle.sh:460`) already derive `LATTICE_HOME_DIR` from the binder — keep; add a bats fault test that runs finish-ledger from `/tmp`-like cwd with an absolute `--binder` and asserts the ledger under the binder home is staged.
3. `transition_table.py`: drop `("any","closed")`; add `pr-open→closed` (merge), `queued→closed` + `in-progress→closed` (merge, metric `direct-jump`), and `{queued,in-progress,parked,stuck,rework,deferred,pr-open}→closed` cancel edges keyed by reason — since `_EDGE_INDEX` is keyed by (from,to), model cancel vs merge as one edge per (from,to) whose `reason` lists both and a `direct_jump` flag; `is_legal_edge` no longer consults `any`. Mirror in the validator's vendored `LEGAL_EDGES_FULL`.
4. `finish-ledger.sh`: when merged and prior_status ∈ {queued,in-progress} → ledger entry reason `merge`, metric `direct-jump`, plus `anomaly:` line (extend the set at :477).
5. Validator: new check `closed_without_ledger` in the ticket pass (terminal status ∧ no `<home>/.transition-ledger/<tkt>.jsonl`); severity by `created` cutoff constant `LEDGER_CUTOFF = 2026-09-02T00:00:00Z`; regenerate `tools/.validator-warning-baseline.txt` for the legacy set (ratchet keeps one-way).
6. `queue_health.py`: coverage row (terminal-with-ledger / terminal) + direct-jump count from ledgers; `queue-health.sh --section` prints both.
7. Docs: `docs/workflow-fsm.md` §2 replace the `any → closed` row with explicit rows; `workflow-fsm-reference.md` mirror; `transition-parity.bats` updated (owner cells).

## Anticipated decisions

- Cancel-vs-merge on the same (from,to) pair — disposition: pre-resolved(spc-337 A2): one edge per pair carrying both reasons + `direct_jump` flag; replay checks reason ∈ edge.reasons.
- Legacy cutoff constant location — disposition: agent-decides (validator module-level constant, documented in ADR-012 §4).
- Baseline regeneration method — disposition: pre-resolved(spc-254 D3): regenerate via the validator's own baseline writer; never hand-edit.

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

(none)

## Attempts

<!-- Fallback ledger (ADR-004 §5). -->

## Notes

## References

- Spec: `spc-337` → `.lattice/specs/spc-337-fsm-conformance-closure.md`
- ADR: `ADR-012` → `docs/adr/012-transitions-stamped-by-the-path.md`
- Review: `rev-20260902-015425Z`

## Lineage

- Parent spec: **spc-337**
- Parent issue (GH sub-issue of Spec primary): **#337**
- Primary ticket: **tkt-338**
- Covers: **A1, A2**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: (serial)
- Worktree bind: tkt-338-ledger-path-explicit-edges-coverage

## Assets

(none)

## Finish

- (none yet)
