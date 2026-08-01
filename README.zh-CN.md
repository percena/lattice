# Lattice

> 面向编码智能体的 Ticket-Driven Development。

[English](./README.md) | 简体中文

Lattice 是一套开源的可移植 Agent Skills 工具包，并附带可选的 Claude Code Hooks，为编码智能体提供一条从产品意图到合并入库 PR 的有纪律的路径。它在本地运行，复用你既有的 Git 与 GitHub 凭证，并已为 [Claude Code](https://claude.ai/code) 与 [Codex](https://openai.com/codex) 完成打包。它是**纪律优先、不做重**——只约束*路径*（每条可发布分支绑定 `tkt-N`/`spc-N`，每个 PR 带上 Why/How/Spec 行），但在每一步内部如何思考、如何写代码则留给模型自己定；护栏是底线，不是天花板。

## 快速开始

每台机器安装一次，然后在任意仓库中开启一个 ticket。

```bash
# 1) 可移植技能（所有受支持的 agent：Claude Code、Codex、Cursor……）
npx skills add percena/lattice -g -y
```

```text
# 2) Claude Code 插件（同样的技能 + 可选 Hooks）
/plugin marketplace add percena/lattice
/plugin install lattice@percena
```

```text
# 3) 在你的仓库中
/start-work
```

高级安装（组织级推广、私有 fork、本地开发、刷新）→ [docs/getting-started.md](./docs/getting-started.md)。

## 循环

`/start-work` 是通用入口——它分类范围并路由进下面的循环（新功能会委托 `/create-spec`；续作已有 ticket 用 `/start-work tkt-N`）。

```text
  /create-spec  |  /create-review
       ↓
  /create-tickets
       ↓
  /start-work
       ↓
  implement
       ↓
  /create-pr
       ↓
  /finish-work
```

```bash
# 1) 规划——锁定范围，拆分为 ticket
/create-spec           # 例如"帮我创建一个付款功能"
/create-tickets

# 2) 执行该 ticket
/start-work tkt-N

# 3) 上线
/create-pr
/finish-work pr N
```

## 理念

**约束路径，不约束脑子。** Lattice 只脚本化主干——Spec → ticket → worktree → PR → merge——保证链路不跳步、不丢血缘。但它*不*脚本化模型每一步内部怎么推理、按什么顺序思考、输出什么句式。强模型保持创造性，框架负责让链路可续作。护栏（worktree 隔离、对齐检查、血缘）是底线，不是天花板。

**本地优先检索，透明的 Memory。** Spec、ticket、review、ADR 都作为模板化本地文件写在 `.lattice/` 下——可 grep、可 review、随仓库一起 commit。绝大部分上下文查询（验收标准、上次 review 结论、一个 spec 拆成了哪几张票）用本地 `cat`/`grep` 毫秒级就能拿到；GitHub 只在需要远端独有事实（issue/PR 实时状态、评论、CI）时才查。Memory 不是框架黑箱——它是你和团队共同拥有、显式的工程产物。

**血缘（Lineage）。** 每次交付留下一条可回头追的链——Spec（`spc-N`）拆成若干 ticket（`tkt-N`），每张票落进一个 PR（`pr-N`），每次 review 是一个 `rev-…`。这些 ID 就是活页夹文件名，所以一条 `grep -r spc-N .lattice/` 就能跨会话、不联网地把整条链捞回来。

## 技能

| 技能 | 用途 | Slash |
| --- | --- | --- |
| [`start-work`](./skills/start-work/) | 分类 S/M/C，绑定 ticket + 工作树，按 id 续作 | `/start-work` |
| [`create-spec`](./skills/create-spec/) | 持久化带验收标准的 Lattice Spec（`spc-n`） | `/create-spec` |
| [`create-review`](./skills/create-review/) | 持久化带显式 outcome 的 Lattice Review（`rev-YYYYMMDD-HHMMSSZ`） | `/create-review` |
| [`create-tickets`](./skills/create-tickets/) | 将已锁定范围拆分为 GitHub issues + 活页夹 | `/create-tickets` |
| [`create-pr`](./skills/create-pr/) | 开启/更新格式规范的 GitHub PR | `/create-pr` |
| [`finish-work`](./skills/finish-work/) | 更新 base、对齐检查、合并、清理 | `/finish-work` |
| [`_lattice-lib`](./skills/_lattice-lib/) | 支撑上述技能的共享脚本（共装，非 slash 入口） | — |

非交付循环——分三类，均不产生血缘节点：

| 类别 | 技能 | 说明 |
| --- | --- | --- |
| PR 范围质量旁路 | [`review-code`](./skills/review-code/) · [`review-production`](./skills/review-production/) | 可选，在 `/create-pr` 前后；不依赖 `_lattice-lib` |
| 独立文档工具 | [`generate-wiki`](./skills/generate-wiki/) | `wiki/` + `llms.txt`；随时可跑；不依赖 `_lattice-lib` |
| 带外伴生（`create-*` 家族） | [`create-adr`](./skills/create-adr/) | 写 `docs/adr/NNN`；共装 `_lattice-lib`；**非血缘节点**——与 `/create-spec`/`/create-review` 同 pass 同 worktree 调用（提升跨特性决策）；绝非循环入口或 Spec 替代品 |

## 文档

| 文档 | 主题 |
| --- | --- |
| [getting-started](./docs/getting-started.md) | 安装、自动 ensure、profiles、日常路径、高级安装 |
| [github-surface](./docs/github-surface.md) | kind + priority 标签、可选 Project 自动添加 |
| [CONTRIBUTING](./CONTRIBUTING.md) | 在本 monorepo 中修改技能/插件 |
| [SECURITY](./SECURITY.md) | 漏洞报告 |
| [CODE OF CONDUCT](./CODE_OF_CONDUCT.md) | 社区规范 |
| [CHANGELOG](./CHANGELOG.md) | 插件 SemVer |

## 环境要求

`git`、`gh`、`jq`、`python3`（≥ 3.8）、`curl`——加一个能运行 [Agent Skills](https://agentskills.io/) 或 Claude Code 插件的智能体。Hook 测试需 `bats`。

## 许可证

MIT——见 [LICENSE](./LICENSE)。

## 致谢

感谢 [linuxdo](https://linux.do) 社区的讨论、分享与反馈。
