---
id: rev-20260830-141357Z
slug: workflow-orchestration-contract-audit
title: Lattice workflow and orchestration contract audit
kind: design
status: concluded
outcome: spawn_spec
summary: "核心红线已显著机械化，但跨阶段编排、远端 mutation 证明、runtime evidence 与血缘闭环仍依赖宿主纪律。"
created: 2026-08-30
updated: 2026-08-30
related_specs:
  - spc-104
  - spc-186
  - spc-213
  - spc-220
  - spc-226
related_tickets: []
related_prs: []
---

# Review: Lattice workflow and orchestration contract audit

> **TL;DR:** Lattice 已从“纯提示词工作流”演进为有可靠原子脚本和静态契约的交付系统；下一阶段不应继续堆叠 Skill prose，而应把跨阶段编排、mutation 证明和 evidence/lineage 契约编译成可恢复、可验证的执行层。
> **Kind:** design · **Status:** concluded · **Outcome:** spawn_spec
> **Next:** 创建一个“Executable workflow contracts”Spec，先锁定 transition/coordinator/evidence 的边界，再拆分修复票据。

## Context

本 Review 响应“完整 review 当前项目，检查设计或工作流改进点”。范围覆盖公开产品承诺、三机 FSM、Spec→Tickets→Start/Batch→PR→Finish 主链、Review/ADR/runtime verification 旁路、L0 artifact validator、Claude hooks、CI 和本项目 dogfood 可靠性。

审查方法：以 `README.md` 和 `docs/workflow-fsm.md` 为外部/规范基线；追踪核心 Skill 与脚本的真实执行路径；对照 `rev-20260829-160834Z`、`spc-186`、`spc-213`、`spc-220`、`spc-226` 及 dogfood retrospective，区分“历史缺口已修复”和“当前仍存在”的问题。本次只做 Review，不修改产品实现，也未依赖远端 GitHub 实时状态。

已确认的进展不能被旧结论覆盖：`spc-186` 已交付 marker gate、状态词汇/side-state guard、Spec supersede trip-time sweep、binder 时间戳和 water-level、fix-cycle cap、CI gate；当前 FSM 也已补齐 Review/verify/S-fast-path entry edges。问题已从“红线完全是 prose”收缩为“跨阶段契约仍没有统一执行与证明”。

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | 问题真实，但因项目在 2026-08-29/30 连续修复，直接复述上一轮 Review 会产生大量假阳性；必须审查当前树而不是历史快照。 |
| Information | 本地代码、Specs、Reviews、CI 与 validator 足以评价设计和工作流。没有阻止结论的 must-have 缺口；未执行远端 GitHub 状态核验，因此不评价线上 issue/PR 的实时一致性。 |
| Hidden issues | 深层问题不是“脚本数量不够”，而是契约分层不完整：原子 mutation 已逐步脚本化，但 orchestrator、proof 和 cross-artifact consistency 仍由宿主模型拼接。继续增加 prose 会扩大实现与声明的漂移面。 |

## Findings

1. **P0 — `process` mode 的完成语义与已勾选 Acceptance 不一致。** `spc-213` A4 要求通过 `claude agents --json` + PID liveness 把节点分类为 `ok | failed | timeout`；当前 `skills/batch-work/scripts/run-process-wave.sh` 明确只根据 PID 报 `completed | timeout`，并把 PR/真实 mutation 验证留给 host。近期的 `spawned-but-dead` grace probe 修掉了“立即崩溃被当 completed”，但一个运行较久后失败、未开 PR 的 worker 仍先被标记 `completed`。这既是 false-success 风险，也是 `status: done` Spec 与实现契约的直接漂移。证据：`.lattice/specs/spc-213-batch-work-process-spawn.md` A4/D3；`skills/batch-work/scripts/run-process-wave.sh` 文件头、`barrier_poll()`、`emit_report()`。

2. **P0 — verify-after-mutate 尚未成为普通交付路径的机械不变量。** 项目已有 `skills/_lattice-lib/scripts/verify-mutation.sh`，batch spawn brief 也要求后验确认；但普通 `create-pr` 路径在 commit/push、`gh pr create` 后只要求 host “accountable verify”，没有把 expected OID、remote branch 和 PR head 的确认编入 canonical short path。dogfood retrospective 已记录吞输出导致 phantom issue/PR/push/merge 的真实事故；仅写“host verifies”不能防止同类宿主误判复发。证据：`skills/create-pr/SKILL.md` Core rule 7、Short path、Verification；`skills/create-pr/references/workflow.md` §4；`skills/_lattice-lib/scripts/verify-mutation.sh`；`.lattice/reviews/rev-20260829-140444Z-spc186-dogfood-retrospective.md` F1/F5。

3. **P1 — FSM 已有 vocabulary SoT，但没有 transition-as-data 与可重放历史。** `status_vocab.py` 和 vendored validator copy 能校验状态词汇、side state 与部分 coupled fields；`docs/workflow-fsm.md` 的完整 transition table、owner、guard、escape 仍没有对应的机器模型。validator 只看当前 snapshot，无法识别两个合法 snapshot 之间的非法边；`spc-186` D5 也明确把 transition replay 延后。结果是每新增 writer 或 host 编排路径，都必须人工保持 docs、Skill prose、脚本和 validator 一致。证据：`docs/workflow-fsm.md` §2/§5；`skills/_lattice-lib/scripts/lib/status_vocab.py`；`tools/validate-lattice-artifacts.py` 顶部 contract 与 status 常量；`.lattice/specs/spc-186-hard-limit-closure.md` Out of scope/D5。

4. **P1 — 两端 DAG 都是“协议完整、执行核心仍依赖宿主上下文”。** `batch-work` 的 DAG build、layer/wave barrier、fuse、binder stamping、stacked base 和最终 report 由 host 按 Skill 编排；process helper 只负责单 wave。`finish-work` multi-PR 的 Kahn sort、layer barrier、retarget、halt/resume 也被 `spc-220` 明确设计为“不新增脚本”的 host-agent prose。协议可读性很好，但缺少 durable batch id、node state、resume cursor 和统一 failure classification；宿主重启或 context 压缩后，恢复点仍主要靠重新解释 artifacts。证据：`skills/batch-work/SKILL.md` BUILD DAG→SPAWN→BARRIER→FUSE→REPORT；`skills/batch-work/scripts/run-process-wave.sh` 文件头；`.lattice/specs/spc-220-batch-finish-dag.md` In scope/Out of scope/A5；`skills/finish-work/SKILL.md` Multi-PR verification。

5. **P1 — “night states never reach merged”的强度取决于调用路径和安装模式，产品边界仍不够显式。** scripted `finish-work` 已有 fail-closed gate，这是已修复项；但 Claude PreToolUse hook 默认 `LATTICE_HOOK_MODE=advisory`，只有 strict 才阻断，缺少 `python3` 时 strict 也按兼容策略 fail-open，而且 hooks 本身是 optional/Claude-specific。因而该不变量对 finish-work/strict-hook 成立，不等于对任意 agent、裸 `gh` 或未安装插件环境成立。当前 README 的“chain never skips a step”和 FSM 的无条件 invariant 容易让用户高估覆盖面。证据：`plugins/lattice/hooks/lib/intercept-gh-pr-common.sh` delivery contract、hook mode、python3 degraded path、batch gate；`skills/finish-work/SKILL.md` Common Rationalizations；`README.md` Philosophy；`docs/workflow-fsm.md` §4。

6. **P1 — runtime evidence 与 lineage 都缺“声明即证明”的交叉校验。** feature-map validator 当前只校验 9 列、非空 oracle 和 status enum；它不证明 `pass` 行对应 story 存在、story header 的 oracle/mutations 一致、evidence JSON 存在且 `status=pass`。同样，L0 validator 能查 ticket→Spec 单边边，却不要求 done Spec 的 `prs` 包含 child binder PR union；当前 `.lattice/specs/spc-186-hard-limit-closure.md` 仍是 `status: done` 且 `prs: []`，而 retrospective 声明 9 tickets/PRs 全部 merged。两者都说明“artifact 声称完成”和“可恢复证据闭环”尚未等价。本次 validator 虽 exit 0，但同时输出 101 条 lazy-migration/format warning；没有 warning baseline/ratchet 时，新回归容易淹没在历史噪声中。证据：`tools/validate-lattice-artifacts.py` feature-map block 与 `onesided_spec_ticket_edge`；`skills/run-e2e/SKILL.md` traceability header/Verification；`.lattice/specs/spc-186-hard-limit-closure.md` front matter；`.lattice/reviews/rev-20260829-140444Z-spc186-dogfood-retrospective.md` F3/Decision；本 Review 验证运行的 validator 输出。

7. **P2 — 本地、两条 CI 与 installed-skill dogfood 环境没有完全同构。** `lattice-scripts.yml` pin Bats 1.13.0；`plugin-hooks.yml` 仍用 Ubuntu apt Bats；`ci-local.sh` 使用 PATH 上任意版本并兼容旧 1.2.x。项目已有 installed-skill 双向 drift detector，但 `start-work`/核心 Skill preflight 默认不运行它。对于一个高度依赖脚本语义和“当前 Skill 就是协议”的项目，这会保留“本地绿、某条 CI 红”或“仓库已修、dogfood 仍执行旧 Skill”的系统性噪声。证据：`.github/workflows/lattice-scripts.yml` Install bats；`.github/workflows/plugin-hooks.yml` Install bats；`tools/ci-local.sh` `bats_shimmed()`/Bats dispatch；`skills/_lattice-lib/scripts/check-installed-skill-drift.sh`；`skills/start-work/SKILL.md` Step 0。

## Recommendations

### 立即修复（应在新 Spec 锁定后优先拆票）

1. **纠正 `spc-213` A4 的实现/声明漂移。** process node 的最终状态必须由 exit/result artifact、`claude agents --json`、PID 和 `verify-mutation --expected-oid` 联合判定；使用 `ok | failed | timeout | unknown`，其中 `unknown` fail-closed 并把 binder stamp 为 `stuck + wait_reason: unblock`。不要把“PID 消失”命名为成功。
2. **把 mutation proof 接入 canonical 主链。** push 后验证 remote OID，PR create 后验证 repo/base/head/body/head OID，merge 后验证 PR merged state 与 base OID；任一 proof 失败时停止 cleanup/ledger 并留下结构化恢复信息。普通路径、batch path 和 delegated path 使用同一 helper contract。
3. **先修 L0 已知漂移，再增强 validator。** 回填 `spc-186.prs`；对 done Spec 校验 child binder PR union，对 Review/Spec reciprocal edges 采用可配置 warning→error 迁移；为现有 warnings 建立 baseline + 只降不升的 ratchet，新增 warning 在 CI 中单独失败，避免 101 条历史噪声掩盖回归；错误信息必须给出可执行修复建议。
4. **统一 Bats 与 dogfood preflight。** 两条 CI pin 同版；`ci-local` 版本不符时明确 degraded 或 fail；仅在 Lattice 自身开发模式下运行 installed-skill drift check，不自动覆盖 installed tree。

### 架构改进（新 Spec 的核心）

5. **建立 versioned executable transition contract。** 定义 machine-readable schema：`from/to/owner/guard/reason/escape/trace/metric`；所有状态 writer 通过一个 transition API；追加最小 transition ledger 供 validator replay。Markdown FSM 应由 schema 生成或至少有 parity test，而不是继续手工复制。
6. **把 batch/finish DAG 下沉为可恢复 coordinator。** coordinator 不负责模型推理，只持久化 DAG、layer、node attempt、PID/PR/OID、marker owner、failure class 与 resume cursor；Skill 负责 scope/brief/异常解释。这样保留“constrain the path, not the model”，同时把路径本身从 LLM context 中移出。
7. **编译 runtime evidence contract。** 为 story header 和结果 JSON 定义 schema；`pass` 必须证明 story path、oracle/mutations、last-verified、结果状态、断言与截图；destructive story 还要有授权 trace。validator 对旧数据先 warning，迁移完成后 error。

### 需要在 Spec 第一轮明确的产品决策

8. **明确 guardrail capability matrix。** 推荐保持跨 agent 兼容性：文档将保证表述为“scripted path = hard gate；strict Claude hook = defense-in-depth；advisory/uninstalled = detection only”，不要声称任意调用路径全局强制。若产品坚持全局 invariant，则需要 portable wrapper/CLI，而不是把 optional hook 改名为 hard guarantee。
9. **暂不统一 Review/ADR/Spec 的远端 ID 分配。** cross-clone race 是真实治理债，但低于 false-success、recovery 和 evidence 闭环；先增加 CI uniqueness/retry，等出现多 clone 冲突数据后再决定是否引入远端 claim service。

## Outcome

**`spawn_spec`** — 建议创建一个 C-class Spec：**Executable workflow contracts — transition replay, recoverable DAG coordination, and evidence proof**。

建议 Spec 的边界：

- 必须包含：F1/F2 的 false-success closure、transition schema/API/ledger、可恢复 coordinator 最小切片、runtime/lineage proof、迁移与兼容策略。
- 必须先决策：marker/optional-hook 的保证边界；schema 是否生成 docs；旧 artifact 采用 warning→error 的迁移窗口。
- 明确不包含：改变模型 deliberation、把业务判断编码成硬规则、替换现有 Skill UX、建立通用工作流平台。
- 验收应以故障注入为中心：worker 非零退出、PID 消失但无 PR、push OID 不匹配、host 重启后 resume、非法 FSM edge、`pass` 无 evidence、done Spec 缺 PR recovery edge。

### Follow-ups

- [ ] 创建上述 Spec，先锁定 capability matrix、transition schema 和 migration policy。
- [ ] Spec 锁定后拆分 F1/F2/F6/F7 的独立票据；优先交付 false-success 与当前 L0 修复。
- [ ] 评估 transition schema 是否构成跨 feature 长期法则；若是，再单独提升为 ADR。

## References

- 产品与 FSM：`README.md`；`docs/workflow-fsm.md`；`docs/day-phase.md`；`docs/morning-triage.md`
- 核心执行：`skills/start-work/`；`skills/create-spec/`；`skills/create-tickets/`；`skills/batch-work/`；`skills/create-pr/`；`skills/finish-work/`
- 契约与验证：`skills/_lattice-lib/scripts/lib/status_vocab.py`；`skills/_lattice-lib/scripts/verify-mutation.sh`；`tools/validate-lattice-artifacts.py`；`tools/ci-local.sh`
- Hooks/CI：`plugins/lattice/hooks/lib/intercept-gh-pr-common.sh`；`.github/workflows/lattice-scripts.yml`；`.github/workflows/plugin-hooks.yml`
- 既有 lineage：`rev-20260829-160834Z`；`rev-20260829-140444Z`；`spc-104`；`spc-186`；`spc-213`；`spc-220`；`spc-226`
