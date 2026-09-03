# tkt-435-batch-autonomy-filter-circuit-breaker

> **TL;DR:** Add --min-autonomy filter (default 3) + circuit breaker budget to batch-work FUSE CHECK
> **Kind:** feat · **Priority:** P2
> **Path:** spc-433 → tkt-435 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/435 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:00:00Z |
| updated | 2026-09-03T09:59:27Z |
| adopted | false |
| summary | batch-work --min-autonomy filter + FUSE CHECK budget circuit breaker |
| spec | spc-433 — Vibe Coding 流程优化 (path: ../../specs/spc-433-vibe-coding-flow-optimization.md) |
| covers | A2, A3 |
| blocked_by | #434 |
| merge_blocked_by | #434 |
| parallel_group | G1 |
| paths | skills/batch-work/**, skills/_lattice-lib/references/fallback-policy.md |
| solo_merge | yes |
| autonomy | 2 |
| **primary_ticket** | tkt-435 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-435-batch-autonomy-filter-circuit-breaker |
| worktree | sibling |
| prs | pr-438 — https://github.com/percena/lattice/pull/438 |

## Acceptance (this slice)

- [x] **A2** batch-work 在拉起夜间调度时，按 `--min-autonomy` 阈值（默认 3）过滤 ticket；低于阈值的 ticket 告警跳过并输出提示
- [x] **A3** (batch-work portion) start-work / batch-work 增加 `--budget` 参数；超限后自动执行熔断流程（debug-dump → [BLOCKED] draft PR → `.lattice/blocked/<tkt>.json` → git clean → 拉起下一条）

## Approach

**A2 — --min-autonomy filter:** Add `--min-autonomy <level>` to batch-work INTAKE (SKILL.md arg-hint + flow.md arg parsing). In RESOLVE TICKETS (flow.md §2), after parsing binder fields, extract `autonomy` and filter tickets below threshold. Never-spawned reason: `autonomy-below-threshold` (ticket stays `queued`, printed in dry-run output). Mirror the existing `not-selected` pattern.

**A3 — Circuit breaker budget:** Add second trip condition to FUSE CHECK (flow.md lines 194-205). Currently `ratio = (failed + stuck) / completed`. Add: `budget_spent > batch_budget_ceiling` → trip. Config key: `batch_budget_ceiling` in `.lattice/config.yaml` (default 60min per spec decision 2). Reuse graceful-drain path. New `wait_reason: budget-exhausted` stamped on never-spawned tickets. Per-wave budget tally in `run-process-wave.sh` `barrier_poll` → after `emit_report`.

Touch-set:
- `skills/batch-work/SKILL.md` — arg-hint + INTAKE step
- `skills/batch-work/references/flow.md` — RESOLVE TICKETS filter + FUSE CHECK budget trip
- `skills/batch-work/scripts/run-process-wave.sh` — barrier_poll budget tally + emit_report budget line
- `skills/_lattice-lib/references/fallback-policy.md` — budget circuit breaker law (§Batch fuse)
- `.lattice/config.yaml` — `batch_budget_ceiling` key (lattice-init.sh seeds it)

## Anticipated decisions

- budget unit: wall-clock minutes (per spec decision 2) — disposition: pre-resolved(spec decision 2)
- budget scope: per-ticket (not per-batch) for start-work, per-batch for batch-work FUSE — disposition: pre-resolved(dry-run: existing timebox is per-ticket)
- wait_reason value: `budget-exhausted` — disposition: pre-resolved(parallels `fuse-halt`)
- never-spawned reason for autonomy filter: `autonomy-below-threshold` — disposition: pre-resolved(parallels `not-selected`)
- whether budget circuit breaker also applies to single-ticket start-work: — disposition: must-ask (cross-ticket: tkt-436 owns start-work --budget)

## Decision journal

(append-only during execution)

## Pending decisions

- The start-work --budget single-ticket timeout (A3 start-work portion) is owned by tkt-436. This ticket implements the batch-work FUSE CHECK budget trip only. The two must agree on the budget unit and default.

## Attempts

(none yet)

## Notes

A3 is split: this ticket covers batch-work circuit breaker (FUSE CHECK + drain + pull next); tkt-436 covers start-work --budget (single-ticket timeout + blocked PR + debug dump).

## References

- Spec: `spc-433`
- Blocked by: tkt-434 (needs autonomy field)
- ADR: ADR-006 (worktree isolation for git clean)
- batch-work existing fuse: `fallback-policy.md` §Batch fuse

## Lineage

- Parent spec: **spc-433**
- Parent issue: **#433**
- Primary ticket: **tkt-435**
- Covers: **A2, A3**
- Blocked by: #434
- Merge blocked by: #434
- Parallel group: G1
- Worktree bind: tkt-435-batch-autonomy-filter-circuit-breaker

## Assets

(none)

## Finish


- pr-438 merged: 2026-09-03T09:58:13Z — https://github.com/percena/lattice/pull/438 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #435 closed: 2026-09-03T09:58:37Z (reason: completed) — https://github.com/percena/lattice/issues/435
