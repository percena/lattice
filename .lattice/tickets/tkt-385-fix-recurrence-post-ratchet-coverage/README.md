# tkt-385-fix-recurrence-post-ratchet-coverage

> **TL;DR:** Add `fix_recurrence` metric (files ≥ N fix commits + subject classes) and post-ratchet coverage (`--created-after`) to lineage-metrics so the ADR-012 soak has a number to judge.
> **Kind:** feat · **Priority:** P2
> **Path:** rev-20260902-080545Z F1/F7 → tkt-385 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/385 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:20:35Z |
| updated | 2026-09-02T09:20:35Z |
| adopted | false |
| summary | lineage-metrics fix_recurrence metric + post-ratchet coverage (--created-after) |
| spec | (none — spawned from rev-20260902-080545Z) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G3 |
| paths | skills/review-lineage/scripts/lineage-metrics.sh, scripts/lib/lineage_metrics.py, scripts/tests/lineage-metrics.bats, scripts/tests/fixtures/metrics/ |
| solo_merge | yes |
| primary_ticket | tkt-385 |
| related_tickets | (none) |
| worktree_bind | tkt-385-fix-recurrence-post-ratchet-coverage |
| worktree | sibling `…/<repo>.worktrees/tkt-385-fix-recurrence-post-ratchet-coverage/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** `fix_recurrence` metric computed and in snapshot JSON (`fix_recurrence.files[]`, `fix_recurrence.subject_classes{}`) + `--md` output.
- [ ] **A2** `--created-after <date>` flag computes `coverage_post_ratchet` (with_ledger, terminal, pct, created_after) in snapshot JSON + `--md` output.
- [ ] **A3** Bats: fixture asserts `fix_recurrence` counts a planted `fix(` commit; fixture asserts `coverage_post_ratchet` excludes a pre-cutoff binder.

## Approach

`git_metrics()` in `lineage_metrics.py:246` already counts `commits_total`, `pr_merges`, `direct_commits`, `finish_stamps`. Add `fix_recurrence`: scan `git log --since <window> --format '%h %s'` for subjects matching `^fix(`, group by file path (from `--name-only`), report files with ≥2 hits + a subject-class breakdown (`fix(tkt-`, `fix(`, `flip`, `backfill`). Add `--created-after <date>` flag: when set, filter the binder set to those with `created` ≥ date (or no `created` row for pre-cutoff binders — exclude them), compute coverage on the subset, and emit `coverage_post_ratchet` alongside the legacy `ledger_coverage`. Snapshot JSON gains `fix_recurrence` and `coverage_post_ratchet`; `--md` gains two delta rows.

**Touch-set:** `skills/review-lineage/scripts/lib/lineage_metrics.py` (git_metrics + coverage functions), `skills/review-lineage/scripts/lineage-metrics.sh` (CLI flag passthrough), `skills/review-lineage/scripts/tests/lineage-metrics.bats` (two new test cases), `skills/review-lineage/scripts/tests/fixtures/metrics/` (planted fixture).

## Anticipated decisions

- `fix_recurrence` threshold — agent-decides: ≥2 `fix(` commits per file per window (codebase default; tunable later).
- `--created-after` flag shape — agent-decides: CLI flag `--created-after <YYYY-MM-DD>` + JSON field `coverage_post_ratchet`.
- ADR-012 cutoff date source — agent-decides: read from `.lattice/config.yaml` `lineage:` block if present, else require `--created-after` arg; no hard-coded date.
- subject-class breakdown categories — agent-decides: `fix(tkt-` / `fix(` (no tkt) / `flip` / `backfill` (matches the rev F1 evidence regex).

## Decision journal

## Pending decisions

## Attempts

## Notes

- Origin: `rev-20260902-080545Z` F1 (recurrence) + F7 (coverage baseline).
- The `fix_recurrence` metric lets the next snapshot show whether ADR-012 §1–§4 bent the curve before §5 is built.
- **L4 overlap note (2026-09-02):** `hotspot-metrics.sh` (tkt-388 / spc-387) already computes per-cluster `fix_commit_count` and `fix_class_diversity` at the path level. This ticket (#385) should focus on: (a) `--created-after` post-ratchet coverage (unique to L1, not in L4), (b) a summary `fix_recurrence` row in the L1 snapshot (total files in ≥2 fix commits — the per-file detail lives in L4). The two sensors are complementary: L1 is per-file, L4 is per-cluster.

## References

- GitHub issue: #385
- Review: `rev-20260902-080545Z` Findings F1 (recurrence) + F7 (coverage baseline)
- Spec: `spc-369` A1 (lineage-metrics.sh)
- ADR: `ADR-012` §4 (conformance sensor), §5 (bot bookkeeping — not yet built)

## Lineage

- Parent spec: (none — spawned from review)
- Parent issue: none (ticket-only)
- Primary ticket: tkt-385
- Related / sub-tickets: (none)
- Covers: (none)
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G3
- Worktree bind: tkt-385-fix-recurrence-post-ratchet-coverage
- Child PRs: (none yet)

## Assets

## Finish

- (none yet)
