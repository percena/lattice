---
id: rev-20260831-073033Z
slug: spc254-24h-closure-recheck
title: spc-254 24-hour closure recheck
kind: dogfood
status: concluded
outcome: spawn_spec
summary: "A6/A9 已闭环；其余 acceptance 仍有机械缺口，需以 spc-270 的 fault-injection program 完成真实闭环。"
created: 2026-08-31
updated: 2026-08-31
related_specs:
  - spc-254
  - spc-270
related_tickets:
  - tkt-255
  - tkt-256
  - tkt-257
  - tkt-258
  - tkt-259
  - tkt-260
  - tkt-261
  - tkt-271
  - tkt-272
  - tkt-273
  - tkt-274
  - tkt-275
  - tkt-276
related_prs:
  - pr-263
  - pr-264
  - pr-265
  - pr-266
  - pr-267
  - pr-268
  - pr-269
---

# Review: spc-254 24-hour closure recheck

> **TL;DR:** 最近 24 小时的实现显著推进了旧 Review 的全部方向，但只有 capability matrix 与环境 parity 基本闭环；process、mutation proof、transition contract、coordinator、evidence 和 warning ratchet 仍有机械缺口，不能以 `spc-254 status: done` 和 A1–A9 全勾选代替代码证明。
> **Kind:** dogfood · **Status:** concluded · **Outcome:** spawn_spec
> **Next:** 由 `spc-270` 锁定六个 fault-injection 修复切片，再创建 child tickets 并从 transition foundation 开始执行。

## Context

本 Review 复核 `rev-20260830-141357Z` 提出的 workflow proof/recovery 问题是否已被最近 24 小时变更解决。审查单位固定为当前 `dev` 的 commit range：

- base: `7dfbd63719f74b716e9066cc7c8d71fc032d039a`
- head: `6a191e0d8bca0a26a2af37517a9c23483ec52f90`
- 40 commits，127 files，`+6651/-292`
- 直接交付链：`spc-254` → `tkt-255..261` → `pr-263..269`

方法：逐项从 Spec A1–A9 追到生产代码、调用路径和 fault-injection tests；检查一跳消费者、local validation、syntax/lint、docs sync、privacy/secrets；不以 ticket/PR closed 或 Spec done 代替代码证明。本次 Review 与 follow-up Spec 同 pass，均落在 `spc-270` 绑定 worktree；未使用仓库根目录的非标准分析目录。

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | 问题真实。最新变更并非空实现：新增 transition schema、mutation helper、process classifier、coordinator、evidence validator、capability matrix 和 parity checks；但“有 helper/test”不等于生产路径闭环。 |
| Information | 本地 commit range、当前代码和测试足以判断 correctness/contract。此前实时 PR checks 受权限限制，故不把远端 CI 作为 closure 证据。 |
| Hidden issues | 最大隐藏问题是 artifact truth：`spc-254` 已 done 且 A1–A9 全勾选，但多个 acceptance 的关键动词（fail-close binder、all writers、resume、only-decrease、fails validator）没有被当前代码兑现。历史 artifact 不重写为进行中；本 Review + `spc-270` 构成 correction edge。 |

## Findings

1. **HIGH — Process failure classification 不会真正 fail-close binder，settle probe 也不具确定收敛性。** `run-process-wave.sh::record_stuck()` 与 `coordinator.py::cmd_record_node()` 只追加 transition JSONL，不原子修改 binder 的 `status`、`wait_reason`、`updated`。默认 timeout 在 coordinator 未启用时可能退化为 no-op。`probe_agents_json()` 没有 bounded timeout 或 PID/ticket correlation，任意全局 failed agent 可污染当前节点；定向 “PID disappears” 测试未在 120 秒内完成。A1 只部分实现。

2. **HIGH — Transition schema 已存在，但 transition API 不是统一 mutation chokepoint，replay 仅验证调用方自报边。** `finish-ledger.sh`、`bump-fix-cycle.sh`、`ratify.sh`、`spec-supersede.sh` 等仍直接改 binder；`stamp-pr-open` 先改 binder、再 best-effort 记 ledger。Replay 不校验相邻 continuity、ticket identity、最后 `to` 与 snapshot 一致，也检测不到漏记。Docs parity 只覆盖 edge 子集，不验证 owner/guard/reason/escape/trace/metric。A3/A4 未完成。

3. **HIGH — Recoverable coordinator 尚未进入真实完整 DAG/finish 路径，并存在 stale-snapshot 并发回退。** coordinator 在 process wave 中显式 opt-in，正常 batch-work 未初始化完整 DAG/marker owner/resume 驱动，finish-work 无接入；`resume` 仅打印 pending JSON。command 在 lock 外读取 state，再合并 stale node，可能把 settled node 覆盖回 pending；attempt 固定为 1，transition record 失败也可能 settle。Coordinator suite 有失败/阻塞用例。A5 未完成。

4. **HIGH — Mutation proof 在单 PR path 有实质进展，但 multi-PR path 使用错误 verifier。** `verify-main-chain.sh` 已覆盖 push/PR/单 PR merge 的部分 proof；然而 multi-PR loop 在成功 merge 后仍调用默认只接受 OPEN 的 `verify-mutation.sh --pr N`，会把正确 MERGED PR 判失败并绕过 base-tip proof。当前 merge stage 仅证明 base tip 与旧 OID 不同，没有证明推进包含目标 PR；并发提交可假阳性。A2 只部分实现。

5. **MED — Runtime evidence validator 验证 pass 标签，不验证完整 evidence payload。** 缺 story、oracle/mutations mismatch、缺 result、destructive 无授权已能拒绝；但 `{ "status": "pass" }` 仍可绕过 identity、last-verified/freshness、非空且全通过 assertions、screenshot、mutation round-trip/leftovers 等 contract。Done-Spec PR union 仍是 warning。A7 只部分实现。

6. **MED — Warning baseline 不是机械 one-way ratchet。** Signature 只有 `code + path`，同文件同 code 的新增 occurrence/detail 会被已有 baseline 吞掉；baseline 缺失/空时 gate 关闭；没有 base-branch subset/size 比较来禁止增长或清除 stale 条目，也没有 reciprocal-edge warning→error 的版本化 schedule。A8 未完成。

7. **POSITIVE — Capability matrix 与 environment parity 基本闭环。** README/FSM 已区分 scripted hard gate、strict hook defense-in-depth、advisory/uninstalled detection-only、missing-python fail-open；两条 CI pin Bats 1.13.0，`ci-local` 对 mismatch 报 DEGRADED，dev-mode installed-skill drift 为 check-only。A6/A9 保持完成，不重复创建修复票。

## Acceptance Reconciliation

| spc-254 Acceptance | 当前判定 | Correction path |
| --- | --- | --- |
| A1 process proof | 部分 | spc-270 A2 |
| A2 main-chain proof | 部分 | spc-270 A4 |
| A3 transition contract | 未完成 | spc-270 A1 |
| A4 schema/docs parity | 部分 | spc-270 A1 |
| A5 recoverable coordinator | 未完成 | spc-270 A3 |
| A6 capability matrix | 完成 | 不重复 |
| A7 evidence proof | 部分 | spc-270 A5 |
| A8 validator migration | 未完成 | spc-270 A6 |
| A9 environment parity | 基本完成 | 不重复 |

## Recommendations

1. **Atomic transition foundation first.** Transition API 在一个锁/事务内读取真实 prior state、校验 edge、更新 status/coupled fields/updated、追加 ledger；迁移全部 status writers；replay 校验 continuity、ticket identity 和 final snapshot。
2. **Deterministic process closure second.** Worker 写 result artifact；probe bounded 且关联 PID/session，不能关联时仅作 advisory；unknown/timeout 使用 atomic transition，任何 non-ok 让 wave 返回机器可判失败。
3. **Production-wire coordinator.** Spawn 前 load 完整 DAG；batch/finish 共用 durable state；lock-before-read patch 或 revisioned CAS；attempt 递增、record-node 幂等、transition 失败不得 settle；resume 实际驱动下一节点。
4. **Converge mutation proof.** Multi-PR 使用与 single-PR 相同的 main-chain verifier，并把 proof 绑定目标 PR 的 merge commit/内容与 base ancestry，而非仅 base OID changed。
5. **Version runtime evidence.** 校验 identity、run timestamp/last-verified、assertions、screenshots、mutation round-trip/leftovers；增加 stale/handwritten-pass fault injection。
6. **True warning ratchet.** 使用稳定 entity key + occurrence/multiset；baseline 缺失 fail closed；CI 与 base baseline 比较，禁止增长、允许删除；warning→error 有版本化 schedule。

## Validation

- `python3 -m py_compile`：transition API/table、coordinator、validator 通过。
- `shellcheck`：`verify-main-chain.sh`、`run-process-wave.sh`、`spawn-ticket-process.sh` 通过。
- transition/schema/capability targeted Bats：21 tests，0 failures。
- A7/A8 targeted Bats：11 tests，0 failures，但 fault coverage 未包含 F5/F6 的深层字段。
- coordinator Bats：存在失败用例与未完成集成用例，suite 非绿。
- A1 targeted Bats：存在未完成用例，suite 非绿。
- artifact validator：`ok=true, errors=0, warnings=101, new_warnings=0`，受 F6 signature 缺口限制。
- `ci-local.sh --fast` 此前未完整结束，不能声称全绿。
- Privacy/secrets：未发现新增 credential/private-key/local-path 泄露。

## Outcome

**`spawn_spec`** — 这些缺口跨越 transition foundation、batch/finish orchestration、runtime evidence 与 CI migration，且有明确依赖图；由 `spc-270` 锁定 correction program，再拆六个 child tickets。历史 `spc-254/tkt-255..261` 保持 closed，不重开、不重复。

### Follow-ups

- [ ] `spc-270` 锁定 A1–A6 fault-injection acceptance。
- [ ] 创建六个 child tickets；transition foundation 是 process/coordinator 的前置，mutation/evidence/ratchet 可并行。
- [ ] 从 transition foundation ticket 执行 `start-work`，完成后按本 Review 矩阵复核。

## References

- Prior Review: `rev-20260830-141357Z`
- Program under review: `spc-254`
- Delivery tickets: `tkt-255`, `tkt-256`, `tkt-257`, `tkt-258`, `tkt-259`, `tkt-260`, `tkt-261`
- PRs: `pr-263`, `pr-264`, `pr-265`, `pr-266`, `pr-267`, `pr-268`, `pr-269`
- Follow-up Spec: `spc-270`
