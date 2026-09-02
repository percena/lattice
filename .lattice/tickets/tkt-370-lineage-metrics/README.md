# tkt-370-lineage-metrics

> **TL;DR:** lineage-metrics.sh + lib/lineage_metrics.py: L1 running-data metrics with schema-versioned JSON snapshot and delta vs previous.
> **Kind:** feat · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/370 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T07:21:07Z |
| updated | 2026-09-02T07:21:07Z |
| adopted | false |
| summary | lineage-metrics.sh + lib/lineage_metrics.py: L1 running-data metrics with schema-versioned JSON snapshot and delta vs previous. |
| spec | spc-369 — review-lineage (path: ../../specs/spc-369-review-lineage.md) |
| covers | A1 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G0 |
| paths | skills/review-lineage/scripts/lineage-metrics.sh, skills/review-lineage/scripts/lib/lineage_metrics.py, skills/review-lineage/scripts/tests/lineage-metrics.bats, skills/review-lineage/scripts/tests/fixtures/metrics/** |
| solo_merge | yes |
| **primary_ticket** | tkt-370 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-370-lineage-metrics |
| worktree | sibling `…/lattice.worktrees/tkt-370-lineage-metrics/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** — see GitHub issue #370 and Spec spc-369 A1.

## Approach

1. `lib/lineage_metrics.py`: import `queue_health` (scan_binders for coverage/direct jumps), `transition_table` (LEGAL_EDGES), `binder_rows` (field parsing) via the `_lattice-lib/scripts/lib` sys.path pattern used by queue-health.sh; functions `collect(home, repo_root, since) -> dict`, `load_previous(snapshot_dir)`, `delta(cur, prev)`, `render_md(cur, delta)`.
2. Metrics: status histogram; ledger coverage; edge histogram from all ledgers vs LEGAL_EDGES → walked/never-walked lists; direct jumps; fix_cycles histogram; side-state + wait_reason counts; sections non-empty counts (Attempts / Pending decisions / Decision journal) via regex; NOTICED lines (count + list of `path — text`); escape traces (`rule_id=…` grep) by rule; git: `git log --format=%s <base> --since` → commits without `(#N)$` vs with; Specs done with open `- [ ]` A*; Spec prs vs child binder prs union.
3. `lineage-metrics.sh`: Step-0 resolver (LATTICE_SKILL_ROOT → resolve-lattice-lib.sh), args `--home --since --snapshot-dir --json --md --no-snapshot`; python3 missing → degrade message (ensure-python3 pattern); writes snapshot then prints.
4. Bats: fixture home under `tests/fixtures/metrics/` with 6 binders (mixed statuses, one with ledger, one NOTICED, one fix_cycles 2), 2 ledgers, 1 done Spec with an open A*; planted previous snapshot to assert delta arrows; `--no-snapshot` leaves the dir untouched; git metrics tested on a tmp repo with two commits (one with `(#1)`).

## Anticipated decisions

- Snapshot dir committed vs ignored — pre-resolved(spc-369 Agent-assumed): committed under .lattice/reviews/metrics/.
- Delta rendering when no previous snapshot — agent-decides (print 'first snapshot').

## Decision journal

## Pending decisions

(none)

## Attempts

## Notes

## References

- Spec: `spc-369` → `.lattice/specs/spc-369-review-lineage.md`
- Review: `rev-20260902-015425Z` (method origin)

## Lineage

- Parent spec: **spc-369**
- Parent issue (GH sub-issue of Spec primary): **#369**
- Primary ticket: **tkt-370**
- Covers: **A1**
- Blocked by: (none)
- Parallel group: G0
- Worktree bind: tkt-370-lineage-metrics

## Finish

- (none yet)
