---
id: rev-20260902-015425Z
slug: fsm-conformance-and-path-scripting
title: "FSM 运行态 vs 设计态 conformance 审计 — ledger 覆盖、缺失 writer、finish 直推、prose:script 比"
kind: audit
status: concluded
outcome: spawn_spec
summary: "设计了 8 态 21 边，生产只走过 5 条边；119/150 binder 无 ledger、最近 3 张票手改 status、ledger 路径按 cwd 解析；finish 需 97 次直推 dev。法则 → ADR-012，交付 → spc-337。"
created: 2026-09-02
updated: 2026-09-02
related_specs:
  - spc-337
  - spc-186
  - spc-254
  - spc-270
related_tickets:
  - tkt-317
  - tkt-323
  - tkt-325
  - tkt-326
  - tkt-327
related_prs: []
---

# Review: FSM 运行态 vs 设计态 conformance 审计

> **TL;DR:** Lattice 的状态机在"设计层"（ADR-004/007、workflow-fsm.md、transition_table.py）已经很完整，但本仓库自身 150 张票的运行数据表明：真正被走过的边只有 5 条，最常走的 `queued → in-progress` 没有任何脚本 writer，119/150 张 closed 票没有 transition ledger，最近 3 张票（tkt-325/326/327）是手改 `status` 行关闭的且 validator 看不见。同时 finish-work 9 天内产生 97 次直推 `dev` 的 bookkeeping 提交，是 strict profile 自己禁止的路径。下一步不是再加状态或再写 prose，而是把状态写入点搬到已经脚本化的位置、把 finish 主路径编译成一个幂等可恢复脚本，并把"ledger 覆盖率"变成 CI 指标。
> **Kind:** audit · **Status:** concluded · **Outcome:** spawn_spec
> **Next:** 操作者已 sign-off（F3 = GitHub Action bot + 单脚本兜底；F7 = frontmatter 迁移放后续 Spec）。法则见 `ADR-012`；conformance 切片由 `spc-337` 交付（A1–A6，5 张票）；F3/F7 实施为后续 Spec。

## Re-verification (second pass, 2026-09-02)

操作者要求逐项复核后再拆票。全部结论在拉取 `7f451a7`（tkt-335）后的当前树上重新验证；修正如下：

| 项 | 结果 |
| --- | --- |
| `.lattice/.ids/` 遗留（原 P2 第 12 条） | **撤回** —— 已被 tracked 的 `.lattice/.gitignore:6` 覆盖，不是泄漏 |
| ci-local `BATS_TEST_TMPDIR`（原第 12 条） | **弱化** —— `ci-local.sh:214-219` 为每个 suite 单独 mktemp，不跨 suite 共享；仅作备注 |
| **新增 F1b（P0）ledger 路径按 cwd 解析** | `transition-api.py:70` `ledger_path()` 用 `LATTICE_HOME or ".lattice"`（相对 cwd），而 `finish-ledger.sh:639`、`stamp-pr-open.sh:512`、`ratify.sh:294`、`bump-fix-cycle.sh:460` 都按 **binder 路径** 派生 `LATTICE_HOME_DIR` 去 `git add`。cwd 不在仓库顶层时 ledger 写到别处、永不入库。实证：tkt-335 的 finish 提交 `7f451a7` 把 status `queued → closed`，但没有任何 `.transition-ledger/tkt-335.jsonl`。这也解释了 tkt-257 的 binder/ledger 不一致 |
| **新增 F0（meta）本机未安装插件** | `~/.claude/plugins/installed_plugins.json` 无 lattice、无 `activated-skills` 目录、settings 无 lattice hooks。dogfood 一直运行在 capability matrix 的 "plugin uninstalled → detection only" 档；CLAUDE.md 的 "machine-enforced" 在本机不成立，这是 tkt-325/326/327 手改能直接进 dev 的直接原因 |
| tkt-335（刚推送）| 修复了 `flip_close` 谓词（issue 校验失败 ⇒ 不翻 status 但照写 Finish ledger ⇒ validator 报 `finish_without_terminal_status` ⇒ 操作者手改绕过）。这是 F1 中 325/326/327 手改的根因，已修；但 F1b 使其 ledger 仍然丢失 |
| F1 其余数据、F2、F3（150 直推 / 97 finish）、F4（`flow.md:468`、`ci-gate-check` 0 命中、marker 措辞 3 处）、F5（`--batch-id` 门控、`coordinator.py:417` `failed` 不翻转、`heartbeat` 0 命中）、F6、F7 | **全部复核成立**（grep/sed 于当前树） |
| anomaly 覆盖范围 | `finish-ledger.sh:477` 仅 `{parked, stuck, deferred}`；`queued`/`in-progress` 的 merge 直跳无 anomaly —— 与 F1 一致 |

## Context

操作者要求结合行业最佳实践对整个项目做一次 review，重点是状态机与流程。此前一周已有五份 FSM 审计（rev-20260827-064527Z → rev-20260831-073033Z），每份都催生了一个 Spec（spc-186 → spc-254 → spc-270 → tkt-323..327），且每个 Spec 都在 24h 内标为 `done`。本次审计刻意换了一个角度：不再对照文档找"未实现的承诺"，而是**用仓库自己的运行数据（binder、ledger、git log）反推状态机实际被怎样使用**，再对照当前代码验证。

方法：通读 README、workflow-fsm.md、day-phase/morning-triage、ADR-004/006/007/011、spc-186/254/270、最近 6 份 review；三路并行代码审计（transition API 与所有 status writer；batch-work/finish-work 编排层；hooks/validator/CI）；所有负载结论均在本 checkout 上用 grep/sed/shell 循环复核。本审计只读，未修改产品代码。

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | 问题真实。前几轮 review 的"承诺 vs 实现"缺口大部分已修（transition-api 已是所有**脚本** writer 的 chokepoint；replay 校验 continuity/identity/final snapshot；capability matrix 与 Bats pin 已闭环）。本轮发现的是另一类缺口：**设计态 FSM 与运行态 FSM 的脱节**，它不会被"再实现一个承诺"修复。 |
| Information | 150 binder、31 ledger、307 commits（08-25 起）、65 bats/1230 tests、validator 输出、全部 SKILL/flow prose 足以定量结论。未查远端 GitHub 实时状态。 |
| Hidden issues | 深层问题是**状态写入点与工作流的自然落点错位**：状态在 prose 里要求 agent"记得去 stamp"，而 agent 已经必经的脚本点（bind worktree、`gh pr create` 成功、merge 成功）没有承担 stamp 责任。ADR-007 自己的论断（advisory 规则在长上下文下静默失效）被本仓库的数据验证了一次。 |
| Existing solution | transition-api.py `commit` 已具备 lock/edge 校验/coupled field/ledger/atomic，是正确的地基；缺的是**调用它的位置**和**覆盖率度量**，不是新机制。 |

## Comparison matrix — F3：merge 后 bookkeeping 归属

| Option | Cost | Code-delta | Risk | Constraints | Capability |
| --- | --- | --- | --- | --- | --- |
| **B — GitHub Action on `pull_request: closed` 跑 finish-ledger + transition commit，bot 提交（推荐）** | 中 | 1 workflow + finish-ledger 免 gh 交互 | 需 bot token 可推 dev；非 GitHub 消费方要 fallback | 保留 ledger 为 project knowledge | 人工 clone 零 base 写；确定性；dev 提交数减半；validator 自动跟跑 |
| Keep status quo — 操作者 cd main clone → checkout base → pull → 手工 commit/push | 0 | 0 | 5 步非原子；issue 先关、ledger 后推；已产出 tkt-317/323 + pr-333/334 修复 | 与 strict profile 自相矛盾 | — |
| C — 不存 mergedAt，改由 reconcile-state 派生；binder 只留 `status` | 低 | validator + morning-triage | 失去离线 grep 血缘（违背 Local-first） | 需网络 | 最少存储 |
| D — 单一 `finish-work.sh --pr N` 幂等可恢复脚本（无 bot） | 中 | 1 脚本 + 步骤状态文件 | 仍需人工 clone 直推 base | 跨平台一致 | 对非 GitHub Actions 消费方是 B 的必要 fallback |

建议：**B 为主、D 为 fallback**（D 无论如何都值得做，见 F4）。

## Findings

### F1 — 设计态 FSM 与运行态 FSM 脱节（P0，实证）

设计：8 个状态、`transition_table.py` 21 条合法边、6 项人工白名单、4 个 side state 各自的 trip-time stamping。运行数据（本仓库 150 binder，全部 `closed`）：

| 指标 | 值 |
| --- | --- |
| ledger 文件 / binder | 31 / 150（119 张 closed 票无 ledger） |
| ledger 条目 / 出现过的不同边 | 51 / **5**（`pr-open→closed` 22、`queued→pr-open` 15、`in-progress→pr-open` 7、`queued→closed` 6、`queued→in-progress` **1**） |
| side state（parked/stuck/rework/deferred）生产出现次数 | 0 |
| `fix_cycles>0` / `wait_reason` 非空 / `## Attempts` 条目 / `## Pending decisions` 条目 | 0 / 0 / 0 / 0 |
| `queued → closed` 直跳（跳过 in-progress 与 pr-open）| 7 张，其中 tkt-272/274/275/276/323/324 是 merge 而非 cancel |
| binder 与 ledger 末态不一致 | tkt-257（binder closed、ledger 末条 pr-open） |
| 最近 5 张票中无 ledger 的 | tkt-325/326/327 —— 由 commit `45d18c8`/`d17e1ca` 直接改 `| status | queued |` → `closed`，无 API、无 ledger |

两个机制性原因让 CI 看不见这些：

1. `validate-lattice-artifacts.py` 的 replay 只遍历**已存在**的 ledger 文件（`if last_to is not None`），没有 ledger 的 binder 不校验 —— 手改 status 行完全静默。
2. `transition_table.py` 的 `("any","closed")` 通配符让 `queued→closed` 合法；finish-ledger 对 merged PR 从非 pr-open 状态写出的条目是 `reason:"merge"` + `guard:"cancel"` + `trace:"Finish ledger (no mergedAt)"`（见 `.lattice/.transition-ledger/tkt-323.jsonl`），而 mergedAt 实际已写 —— ledger 在自我矛盾。finish-ledger 对 parked/stuck/deferred 已有 `anomaly:` 行，但对 queued/in-progress 没有。

行业对照：状态机的价值来自 conformance，"能建模"不等于"被走过"。标准做法是 (a) **paved road** —— 正确路径必须比绕过更省事；(b) **覆盖率是一等指标** —— ADR-007 §8 把 escape 计数作为边界传感器，但漏掉了更基础的"ledger 覆盖率"；(c) 通配边是 lint 黑洞，cancel 应是显式带 `--reason` 的边。

### F2 — 缺 writer 的边恰好是最常走的边（P0）

`docs/workflow-fsm.md` §2 中以下边**没有任何脚本 writer**，只有 prose 让 agent 手改文件：`queued→in-progress`（start-work / batch-work 都只在 prose 里说"stamp in-progress"，`ensure-workspace.sh` 不 stamp）、`in-progress→parked`、agent fallback-bounds 的 `in-progress→stuck`、fuse-halt / blocked-by-failure 的 `→deferred`（grep `fuse-halt` 在 `*.sh/*.py` 零命中）、`deferred→queued`、`stuck→queued`、`rework→in-progress`、`pr-open→pr-open`（rebase-void 不记录）。F1 的数据（`queued→in-progress` 全仓库只记录 1 次）是这个缺口的直接后果。

这些边的自然落点其实都**已经是脚本**：

| 边 | 已存在的必经脚本点 | 现状 |
| --- | --- | --- |
| `queued→in-progress` | `ensure-workspace.sh --bind tkt --id N` 成功 | 不 stamp |
| `in-progress→pr-open` | `gh pr create` 成功（hook 已拦截该命令） | 靠 prose 提醒 agent 事后跑 `stamp-pr-open.sh`，15 次直跳说明经常忘 |
| `→deferred`（fuse/blocked） | batch-work barrier（`run-process-wave.sh` 已计算 failed/timeout） | fuse 比例本身也是 prose 计算 |
| `deferred/stuck→queued`、cancel | 晨间 triage | 人手改 Markdown |

ADR-006 已经证明"把规则放到 hook 里、把敏感写操作绑到 sentinel"是可行的（L1/L3 + `ensure-workspace` sentinel）。同一模式可直接复用到 `| status |` 行：L3 hook 对 binder 的 `status` 行变更要求 transition-api 的 sentinel，否则拒绝。

### F3 — Finish bookkeeping 需要直推集成分支（P1）

08-25 以来 `dev` 上 PR merge 提交 157 次，**非 PR 直推 150 次**，其中 97 次是 `finish(...)` ledger stamp。每次 finish 的最后一步要求操作者"cd 到 main checkout → checkout base → pull → `finish-ledger.sh` → `git commit` → `git push` → 断言 index 干净"（`skills/finish-work/SKILL.md` step 10）——这正是 strict profile 用 L3 hook 禁止的"main clone 上的 shippable 写"，每次都靠 finish-work 自己的豁免通过。序列非原子且顺序反了：`close-fixed-issues.sh`（step 8）先关 issue，ledger 在 step 10 才 push；push 失败时 GitHub 已 closed 而远端 binder 仍 pr-open，没有可恢复 helper。已观测到的成本：tkt-317（SKILL 曾错误声称 helper 自己 commit）、tkt-323、pr-333/pr-334 两个"flip binder status to closed"修复 PR、三次 "ledger reason refinement (idempotent re-stamp)" 提交。

行业对照：merge 后 bookkeeping 是事件驱动的确定性工作，归属于 CI/bot（`pull_request: closed` + `merged == true`），不归属于人的工作副本；stored state 与 derived state 要分开，GitHub 已是 mergedAt 的 SoT。见上方 Comparison matrix。

### F4 — finish-work 主路径 prose:script ≈ 2.5:1，且 prose 已经漂移（P1）

finish-work 的 SKILL.md + references 共 11.9k 词（全部 skill prose 79k 词，核心六 skill 约 45k 词）；单 PR short path 11 步中脚本调用 6 个、手工步骤约 16 个；multi-PR §7 明确"host-owned (no script)"，超过 3:1。已验证的漂移：

- `references/flow.md:468` multi-PR 每次 merge 后仍调用 `verify-mutation.sh --pr <N>`，其默认只接受 OPEN（`verify-mutation.sh:175-179`）——一次**成功**的 batch merge 会被判 FAILED 并 halt。rev-20260831 F4 标记为 tkt-272 修复，但只修了单 PR 路径的 `verify-main-chain.sh`，prose 路径未同步。
- `ci-gate-check.sh`（spc-186 A6 的硬规则）在 `SKILL.md` 中 **0 次出现**，只在 flow.md；SKILL step 3 写的是"Preflight (draft, checks, mergeable)"由人执行。
- `SKILL.md` 三处仍说 marker 位于 "repo MAIN clone `.lattice/`"，ADR-011 已迁到 `$XDG_STATE_HOME`。
- `PRE_MERGE_BASE`（merge proof 的 expected OID）靠手工 `git ls-remote` 捕获。

行业对照：确定性路径应是**一个**幂等、可恢复的编排脚本（步骤状态文件 + 重入），LLM 只处理真正需要判断的两点（mini-review Hold/Merge、Spec 是否完整）。这正是 README "constrain the path, not the model" 对 finish-work 的字面应用；当前是"用 11.9k 词 prose 描述路径"。

### F5 — coordinator 在真实路径中休眠；`failed` 不回落 binder（P1）

- `run-process-wave.sh` 只有传入 `--batch-id` 才启用 coordinator（`:99` 注释 "DEFAULT-ON: when set"，`:356` 注释 "stays opt-in"，自相矛盾）；`batch-work/SKILL.md:125` 与 `flow.md:218-224` 的调用**不传** `--batch-id`；`load-dag` / `set-marker-owner` 在测试之外零调用；`resume` 只打印 JSON。spc-270 A3 已勾选，但生产 wiring 缺失 —— 与 rev-20260831 指出的 "artifact truth" 问题同型，隔一轮再次出现。
- `coordinator.py:417`：只有 `unknown|timeout` 走 `_commit_stuck`，`failed` "records the failure class only" —— binder 停在 `in-progress`，正是 FSM-2b（rev-20260827-102420Z F2）修过的"abandoned in-progress"回归。
- ADR-011 声称 "batch-work re-touching the marker each wave (heartbeat)"，代码中 `heartbeat` 零命中；`marker_owner.pid` 存了但从不检查。
- marker 由 prose 里的裸 `printf > .../.batch-work-active` 创建，`batch-merge-gate.sh` 没有 `--create`，创建与删除不对称。
- agent 模式（默认）零脚本：DAG、独立性、barrier、fuse、report 全部 host prose。

### F6 — Spec（M1）生命周期没有 transition API，`done` 是自报的（P1）

spc-254 与 spc-270 都在创建当日标 `done`、A* 全勾，下一轮 review 分别判定 A1–A5/A7/A8 部分或未完成、A3 wiring 缺失。`spec_done_open_acceptance` 是 error，但勾选本身无机器依据；`spec_prs_missing_child_union` 仍是 warning。Spec 的 `draft|locked|done|superseded` 没有 lock/edge/ledger，`finish-work` 的 Spec close 是手工 `gh issue close` + 改 frontmatter。

行业对照：Definition of Done 应可执行 —— 每条 acceptance 绑定一个测试/故障注入用例 id，`done` 的 guard 是"全部子票 closed ∧ PR union 完整 ∧ 绑定测试在 CI 绿"。另一个便宜规则：**一个 dogfood 周期后才允许 done**（本周三次"次日被推翻"已足够说明）。

### F7 — 机器状态存放在 Markdown 表格行（P2，设计债）

Spec/Review 用 YAML frontmatter，ticket binder 用 `| field | value |` 表格并由 6 个脚本各自 regex 解析（`binder_rows.py` 只是部分统一）。解析类 bug 反复出现：tkt-149（ratify status 贪婪匹配）、tkt-91/80（prs row 语法）、tkt-323，validator 仍报 `prs_row_format`。建议 ticket 机器字段迁到 frontmatter（与 spec/review 一致，lazy migration，表格保留为渲染视图或删除），一个 parser。

## Recommendations

**P0 — 让运行态回到设计态（可立即拆票）**

1. **Ledger 覆盖率成为 CI 指标 + ratchet。** validator 新增 `closed_without_ledger`（对 `created` 晚于 spc-254 落地日的 binder 为 error，旧票进 baseline）；queue-health 输出 "ledger coverage" 与 "direct-jump 计数"。
2. **拆掉 `any→closed` 通配。** `pr-open→closed`（merge）与 `*→closed`（cancel，必须 `--reason`）分开；finish-ledger 对 merged PR 从 queued/in-progress 关闭时写 `anomaly:` 行并用 `direct-jump` metric 计数，而不是 `guard:"cancel"`。
3. **把 writer 放到必经脚本点。** `ensure-workspace.sh --bind tkt` 成功 ⇒ `transition-api commit queued→in-progress`（幂等，已 in-progress 则 no-op）；`gh pr create` 成功 ⇒ PostToolUse hook（或 `create-pr` 的脚本步骤）自动 `stamp-pr-open`；为人工边提供 CLI（`transition-api.py commit <tkt> queued human --reason …`）并在 morning-triage.md 用命令替换"手改 status"。
4. **L3 hook 守护 `| status |` 行。** 复用 ADR-006 sentinel 模式：Edit/Write 若改动 binder status 行且无 transition-api sentinel ⇒ 拒绝并给出命令。

**P1 — 把确定性路径编译成脚本**

5. **finish-work 单脚本化**（Option D）：`finish-work.sh --pr N` 覆盖 marker gate → update base → alignment → ci-gate → merge → main-chain proof → close issues → cleanup → ledger，步骤状态文件支持重入；LLM 只接管 mini-review 与 Spec-complete 两个判断点。顺手修 `flow.md:468` verifier、SKILL 中 marker 位置、补 `ci-gate-check.sh`。
6. **merge 后 bookkeeping 交给 bot**（Option B，需决策）：`finish-ledger.yml` on `pull_request: closed`，用 bot 身份提交 ledger；消费方无 Actions 时退化为 5。
7. **coordinator 二选一：默认接线或删除。** 若保留：SKILL/flow 传 `--batch-id`，`failed` 也走 `_commit_stuck`，实现或删除 heartbeat 声明，`batch-merge-gate.sh --create` 替代裸 printf。
8. **Spec transition API + 可执行 DoD。** `transition-api.py --kind spec`；`done` guard 绑定子票/PR union/测试 id；引入 "one dogfood cycle before done"。

**P2 — 卫生与降噪**

9. binder 机器字段迁到 frontmatter（需决策）。
10. `reconcile-state.sh` 接入 start-work Step 0（只读、advisory）与 nightly CI；96/101 条 `missing_binder_timestamp` 用一次性 backfill 清掉，让 ratchet 有意义。
11. hooks 一致性：L1/L3 不读 `LATTICE_HOOK_MODE`（永远 block），三个 gh 拦截读 —— capability matrix 应如实写出；skill-activation marker 在 session 内持续到 compaction，建议 Stop hook 清除或短 TTL。
12. `main` 落后 `dev` 286 提交（上次 release 08-25），按 ADR-005 应有 release 节奏；tkt-323..327 五张票 Approach 仍是占位、Acceptance 为 "See GitHub issue"，违反 self-contained artifact 不变量；备注：`ci-local.sh` 的 per-suite `BATS_TEST_TMPDIR` 在 bats 1.2.x 下仍是 suite 内共享。
13. **暂缓扩展 M3。** decision-policy/fallback-policy 约 6k 词，生产数据：Attempts 0、Pending decisions 0、ratified ×2 promotion 未观测、preferences 3 条 —— 先在 queue-health 里计数"policy exercised"，有数据再增机制。

## Outcome

`spawn_spec` — 操作者 sign-off：(a) F3 = GitHub Action bot + 单脚本兜底（ADR-012 §5，后续 Spec 实施）；(b) F7 = frontmatter 迁移放后续 Spec（ADR-012 §7）；(c) 本次交付 conformance 切片 `spc-337`（A1 ledger 路径+覆盖率、A2 显式终态边、A3 路径点盖章、A4 L3 守护、A5 finish prose 修复、A6 coordinator 接线），5 张票，T1 串行打底后 T2–T5 并行。

### Follow-ups

- [x] 操作者决策 F3 / F7（2026-09-02，本 Review 同 pass）。
- [x] `ADR-012` + `spc-337`（同 worktree co-create）。
- [ ] `spc-337` 跑过一个 dogfood 周期后，开后续 Spec 实施 ADR-012 §5–§7（bot bookkeeping、finish 单脚本、Spec DoD、binder frontmatter）。

## References

- 状态与写入：`skills/_lattice-lib/scripts/transition-api.py`；`lib/transition_table.py`；`finish-ledger.sh`；`stamp-pr-open.sh`；`ensure-workspace.sh`；`.lattice/.transition-ledger/*.jsonl`
- 编排：`skills/batch-work/scripts/run-process-wave.sh`；`lib/coordinator.py`；`skills/finish-work/SKILL.md`；`references/flow.md`
- 校验与 hooks：`tools/validate-lattice-artifacts.py`；`tools/.validator-warning-baseline.txt`；`plugins/lattice/hooks/`
- 前序：rev-20260829-160834Z、rev-20260830-141357Z、rev-20260831-073033Z；ADR-004/006/007/011；spc-186/254/270
