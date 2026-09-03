# tkt-436-start-work-budget-unattended-snapshot

> **TL;DR:** Add --budget (60min/5 retries), --unattended mode, and .lattice/snapshots/ context cards to start-work
> **Kind:** feat · **Priority:** P2
> **Path:** spc-433 → tkt-436 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/436 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:00:00Z |
| updated | 2026-09-03T09:59:30Z |
| adopted | false |
| summary | start-work --budget + --unattended mode + .lattice/snapshots/ context cards |
| spec | spc-433 — Vibe Coding 流程优化 (path: ../../specs/spc-433-vibe-coding-flow-optimization.md) |
| covers | A3, A4, A6 |
| blocked_by | #434 |
| merge_blocked_by | #434 |
| parallel_group | G1 |
| paths | skills/start-work/**, skills/_lattice-lib/references/decision-policy.md |
| solo_merge | yes |
| autonomy | 2 |
| **primary_ticket** | tkt-436 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-436-start-work-budget-unattended-snapshot |
| worktree | sibling |
| prs | pr-438 — https://github.com/percena/lattice/pull/438 |

## Acceptance (this slice)

- [x] **A3** (start-work portion) start-work 增加 `--budget` 参数（默认 60min / 5 retries）；超限后自动：打包 debug-dump → 调用 finish-work 生成 [BLOCKED] Draft PR → 写 `.lattice/blocked/<tkt>.json` 阻碍报告 → git clean 重置环境
- [x] **A4** start-work 支持 `--unattended` 标志；该模式下 System Prompt 注入"遇歧义自主决策 + `Auto-Decided:` 注释 + ADR 记录"规则，严禁中断等待用户输入
- [x] **A6** 任务执行完一轮后生成 `.lattice/snapshots/<tkt>.md` 卡片（三字段：本次交付摘要 / 偏离声明 / 待决问题）；start-work resume 时优先读取快照卡片

## Approach

**A3 — --budget for start-work:** start-work has no shell arg parser — `--budget` is an intake token the agent interprets in Step 1 (INTAKE + CLASSIFY). Add `--budget <minutes>,<retries>` to `argument-hint` in SKILL.md. In EXECUTE step 7, apply fallback-policy.md caps: if elapsed > budget or retries > limit, stamp `status: stuck` + `wait_reason: unblock` via transition-api.py `in-progress → stuck` edge. Then: generate `.lattice/blocked/<tkt>-debug-dump.json` (context, last error, attempt count), call finish-work to create [BLOCKED] draft PR, `git clean` reset. The `batch_timebox_*` config keys already exist — --budget overrides for this single run.

**A4 — --unattended mode:** Add `--unattended` to `argument-hint`. In EXECUTE step 7, activate decision-policy.md resolution chain (total function: resolve-or-park, never block). System prompt injection: "遇到歧义自主选置信度最高方案，在代码中打 `// Auto-Decided: <reason>` 注释 + PR body 设 `## Auto-Decided` section + 记录 ADR。" SKILL.md:166 already says "Non-interactive / CI: do not invent PCA answers — fail closed" — --unattended flips this from edge case to active mode.

**A6 — Context snapshot cards:** After EXECUTE completes a round (before VERIFY or handoff), write `.lattice/snapshots/<tkt>.md` with 3 sections: `## Delivered` (what was done), `## Deviations` (what was auto-decided or deviated from spec), `## Pending` (open questions for human). On resume (Step 2), if snapshot exists, read it first before loading full binder. Snapshots are gitignored (temporary state, not durable like binder).

Touch-set:
- `skills/start-work/SKILL.md` — arg-hint, INTAKE step, EXECUTE step 7, resume step 2
- `skills/start-work/references/full-flow.md` — EXECUTE handoff + budget trip flow
- `skills/_lattice-lib/references/decision-policy.md` — unattended chain activation section
- `.lattice/snapshots/` — new directory (gitignored)
- `.lattice/blocked/` — new directory (committed: blocked reports are durable)
- `.gitignore` — add `.lattice/snapshots/`

## Anticipated decisions

- --budget default: 60min / 5 retries (spec decision 2) — disposition: pre-resolved(spec decision 2)
- --unattended system prompt injection format: inline in SKILL.md EXECUTE step — disposition: agent-decides (reversible doc edit)
- Auto-Decided comment format: `// Auto-Decided: <reason>` (spec decision 3) — disposition: pre-resolved(spec decision 3)
- snapshot file path: `.lattice/snapshots/<tkt>.md` (spec decision 4) — disposition: pre-resolved(spec decision 4)
- snapshot lifecycle: gitignored, created on round-end, consumed on resume, deleted on finish-work merge — disposition: agent-decides
- blocked report path: `.lattice/blocked/<tkt>-debug-dump.json` — disposition: agent-decides (parallels .transition-ledger/)
- whether --unattended bypasses strict profile worktree enforcement: — disposition: pre-resolved(ADR-006 is invariant, --unattended does not bypass)

## Decision journal

(append-only during execution)

## Pending decisions

- Should `.lattice/blocked/` be committed (like .transition-ledger/) or gitignored (like snapshots/)? Spec says blocked reports are durable evidence, so committed is likely correct, but needs confirmation.

## Attempts

(none yet)

## Notes

A3 is split: this ticket covers start-work --budget (single-ticket timeout + blocked PR + debug dump); tkt-435 covers batch-work FUSE CHECK budget trip + drain + pull next.

## References

- Spec: `spc-433`
- Blocked by: tkt-434 (needs autonomy field for --unattended decisions)
- ADR: ADR-006 (worktree discipline — --unattended does not bypass)
- decision-policy.md (self-decision chain — --unattended activates it)
- fallback-policy.md (caps — --budget overrides per-run)
- transition-api.py (in-progress → stuck stamp chokepoint)

## Lineage

- Parent spec: **spc-433**
- Parent issue: **#433**
- Primary ticket: **tkt-436**
- Covers: **A3, A4, A6**
- Blocked by: #434
- Merge blocked by: #434
- Parallel group: G1
- Worktree bind: tkt-436-start-work-budget-unattended-snapshot

## Assets

(none)

## Finish


- pr-438 merged: 2026-09-03T09:58:13Z — https://github.com/percena/lattice/pull/438 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #436 closed: 2026-09-03T09:58:41Z (reason: completed) — https://github.com/percena/lattice/issues/436
