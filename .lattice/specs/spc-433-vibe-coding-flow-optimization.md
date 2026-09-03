---
id: spc-433
slug: vibe-coding-flow-optimization
title: "Vibe Coding 流程优化 — 自治度评分 + 断路器 + 推测执行 + 上下文快照"
kind: feat
status: locked
mode: C
priority: P2
summary: "4 个 workflow 改进：ticket 自治度 0-4 评分 + 断路器超限熔断 + 无人值守推测执行 + 上下文快照卡片"
created: 2026-09-03
updated: 2026-09-03
tickets: [tkt-434, tkt-435, tkt-436, tkt-437]
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Vibe Coding 流程优化 — 自治度评分 + 断路器 + 推测执行 + 上下文快照

> **TL;DR:** 给 lattice 的 ticket/workflow 增加昼夜调度智能：自治度评分（0-4）让夜间批处理只跑安全 ticket，断路器防单点卡死，推测执行让无人值守不停摆，上下文快照压缩多轨切换成本。
> **Kind:** feat · **Status:** draft · **Mode:** C · **Priority:** P2
> **Path:** spc-433 → (tickets pending) → (prs pending)

## Why

当前 lattice 的 workflow pipeline（create-spec → create-tickets → start-work → create-pr → finish-work）已覆盖"白天交互式开发"的全链路，batch-work 也已实现 DAG-orchestrated 并行调度。但两个场景仍有明显 gap：

1. **夜间无人值守易卡死**：batch-work 按 DAG 依赖分组拉起 ticket，但不区分"这条 ticket 能否安全无人值守"。自治度低的 ticket（架构歧义、需 UI 确认）在夜间跑到一半就停下等用户确认，整条流水线阻塞。第二天早上一看，实际上只跑了十几分钟就卡在第一个确认点。

2. **单 ticket 无超时熔断**：start-work 没有执行时间或迭代次数上限。一个 ticket 可以无限重试直到 Agent 自己放弃或人工介入，在夜间场景下单点阻塞全盘。

3. **多轨交替的 context-reloading 成本**：白天交替推进多条需求线时，每次切回某条线都要重新阅读 binder 和对话记录来恢复上下文，精力被快速榨干。

来源：Gemini AI Studio 聊天记录"Vibe Coding 的流程优化方案"中的策略启发，经 lattice gap 分析筛选出 4 个高 ROI 且与现有架构兼容的改进点。不包含红蓝对抗（review 三级已覆盖）、骨架 PR（Spec 已锁契约）、WIP 限制（strict profile 已强制一 worktree 一 ticket）、ARCHITECTURE.md lint（非 lattice 范畴）。

## In scope

- **自治度评分（Autonomy Score 0-4）**：create-tickets 为每条 ticket 产出 `autonomy` 字段；batch-work 夜间调度按阈值过滤
- **断路器（Circuit Breaker）**：start-work / batch-work 增加 `--budget` 参数（时间 + 迭代次数）；超限后自动 [BLOCKED] PR + 阻碍报告 + 环境重置
- **推测执行 + Auto-Decided 标签**：start-work 增加 `--unattended` 模式；遇歧义自主决策 + 代码注释标记；review-code 高亮审阅
- **上下文快照卡片（Context Snapshot）**：执行完一轮后生成 `.lattice/snapshots/<tkt>.md` 三字段卡片；start-work resume 时优先读取

## Out of scope

- 红蓝对抗双 Agent 辩论机制（review-code + review-production + review-delivery 三级已覆盖"挑刺"需求）
- 骨架 PR / Contract-first（create-spec 已锁定 Acceptance Criteria + Decisions，契约在 Spec 阶段就定了）
- WIP 限制（strict profile 已强制一 worktree 一 ticket）
- ARCHITECTURE.md + 自动化架构 lint（属于业务代码库范畴，非 lattice workflow 框架职责）
- 多模态验收凭证（截图/动图贴 PR）— 可作为后续 follow-up spec

## Acceptance

- [ ] **A1** create-tickets 产出的 ticket binder 包含 `autonomy` 字段（0-4 整数），并有自评规则文档
- [ ] **A2** batch-work 在拉起夜间调度时，按 `--min-autonomy` 阈值（默认 3）过滤 ticket；低于阈值的 ticket 告警跳过并输出提示
- [ ] **A3** start-work / batch-work 支持 `--budget <minutes>,<retries>` 参数；超限后自动执行熔断流程（debug-dump → [BLOCKED] draft PR → `.lattice/blocked/<tkt>.json` → git clean → 拉起下一条）
- [ ] **A4** start-work 支持 `--unattended` 标志；该模式下 System Prompt 注入"遇歧义自主决策 + `Auto-Decided:` 注释 + ADR 记录"规则，严禁中断等待用户输入
- [ ] **A5** review-code 在审阅时默认高亮 `Auto-Decided` 标记的代码行，列入重点审阅清单
- [ ] **A6** 任务执行完一轮后生成 `.lattice/snapshots/<tkt>.md` 卡片（三字段：本次交付摘要 / 偏离声明 / 待决问题）；start-work resume 时优先读取快照卡片而非从头解析 binder

## Non-goals

- 不改变 strict profile 的 worktree 强制策略
- 不替代现有的 review 三级体系
- 不引入新的 review skill

## Decisions (principal, user-confirmed)

1. **自治度编号从 0 开始**（0=Day-Interactive, 1=低自治, 2=中自治, 3=高自治, 4=全自治），与 lattice 优先级从 0 开始编号的惯例一致。— user-confirmed
2. **断路器默认预算**：60 分钟 / 5 次重试，可通过 `--budget` 覆盖。— user-confirmed
3. **Auto-Decided 标签格式**：代码中使用 `// Auto-Decided: <reason>` 注释格式，PR body 中设 `## Auto-Decided` section 汇总。— recommended
4. **上下文快照存储路径**：`.lattice/snapshots/<tkt>.md`，与 binder 同级但不入 binder 目录（快照是临时态，binder 是持久态）。— recommended
5. **夜间自治度准入阈值默认 3**：≥3 才进入夜间 batch-work 调度。<3 的告警跳过。— recommended

## Agent-assumed (secondary)

- 断路器的 debug-dump.json 存放在 `.lattice/blocked/<tkt>-debug-dump.json`
- `--unattended` 模式下 Supervisor 决策仍受 CLAUDE.md + ADR 约束，不绕过 worktree 纪律
- 快照卡片在 finish-work 成功 merge 后自动清理（gitignored）

## Risks / open questions

- 自治度评分的准确性依赖 create-tickets Agent 的判断质量，初期可能需要人工校准
- 断路器的"5 次重试"计数粒度需定义：是同一次 start-work 内的重试，还是跨多次 start-work 的累计？
- `--unattended` 模式下 Agent 自主决策出错时的回滚成本 — 需确保 git worktree 隔离能兜底
- 快照卡片与现有 transition-ledger / finish-ledger 的关系需厘清，避免职责重叠

## References

- Prior Spec: spc-145（worktree 纪律 hard-enforcement）— 本 spec 的断路器依赖 worktree 隔离
- ADR: ADR-006（worktree discipline）— 断路器环境重置基于此
- ADR: ADR-009（e2e platform strategy）— 多模态凭证 follow-up 将基于此
- Skill: `batch-work`（DAG-orchestrated 并行调度）— 自治度过滤 + 断路器集成于此
- Skill: `start-work`（workspace bind + implement）--budget/--unattended 集成于此
- Skill: `create-tickets`（ticket 产出）— autonomy 字段产出于此
- Skill: `review-code`（PR-scoped review）— Auto-Decided 高亮集成于此

## Links / bloodline (L0)

- Tickets: (pending — will be created by create-tickets)
- PRs: (pending)
- Reviews: (none)
